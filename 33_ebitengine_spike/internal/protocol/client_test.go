package protocol

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestClientUsesDeterministicIDsAndResetsTarget(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	var mutex sync.Mutex
	var ids []uint64
	done := make(chan error, 1)
	go func() {
		for range 2 {
			connection, err := listener.Accept()
			if err != nil {
				done <- err
				return
			}
			line, err := bufio.NewReader(connection).ReadBytes('\n')
			if err != nil {
				_ = connection.Close()
				done <- err
				return
			}
			var request Request
			if err := json.Unmarshal(line, &request); err != nil {
				_ = connection.Close()
				done <- err
				return
			}
			mutex.Lock()
			ids = append(ids, request.ID)
			mutex.Unlock()
			err = json.NewEncoder(connection).Encode(map[string]any{
				"id": request.ID,
				"result": map[string]any{
					"method": request.Method,
				},
			})
			_ = connection.Close()
			if err != nil {
				done <- err
				return
			}
		}
		done <- nil
	}()

	client := newTestClient(t, listener.Addr().String())
	result := struct {
		Method string `json:"method"`
		Stale  bool   `json:"stale"`
	}{Stale: true}
	for _, method := range []string{
		MethodRuntimeGetState,
		MethodWorldGetSnapshot,
	} {
		result.Stale = true
		if err := client.Call(
			context.Background(),
			method,
			nil,
			&result,
		); err != nil {
			t.Fatal(err)
		}
		if result.Method != method || result.Stale {
			t.Fatalf("target was not freshly decoded: %+v", result)
		}
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	mutex.Lock()
	defer mutex.Unlock()
	if !reflect.DeepEqual(ids, []uint64{1, 2}) {
		t.Fatalf("request IDs = %v, want [1 2]", ids)
	}
}

func TestClientValidatesResponseEnvelope(t *testing.T) {
	cases := []struct {
		name     string
		response string
		contains string
	}{
		{
			"ID mismatch",
			`{"id":99,"result":{}}`,
			"ID mismatch",
		},
		{
			"both result and error",
			`{"id":1,"result":{},"error":{"code":"x","message":"x"}}`,
			"exactly one",
		},
		{
			"neither result nor error",
			`{"id":1}`,
			"exactly one",
		},
		{
			"unknown field",
			`{"id":1,"result":{},"extra":true}`,
			"unknown field",
		},
		{
			"duplicate field",
			`{"id":1,"id":1,"result":{}}`,
			"duplicate",
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			address := startOneShotWireServer(t, func(
				_ Request,
			) string {
				return test.response
			})
			client := newTestClient(t, address)
			_, err := client.CallRaw(
				context.Background(),
				MethodRuntimeGetState,
				nil,
			)
			if err == nil ||
				!stringsContainsFold(err.Error(), test.contains) {
				t.Fatalf(
					"error = %v, want text containing %q",
					err,
					test.contains,
				)
			}
		})
	}
}

func TestClientReturnsStructuredRemoteError(t *testing.T) {
	address := startOneShotWireServer(t, func(request Request) string {
		return fmt.Sprintf(
			`{"id":%d,"error":{"code":"not_found","message":"missing","data":{"id":"ghost"}}}`,
			request.ID,
		)
	})
	client := newTestClient(t, address)
	_, err := client.CallRaw(
		context.Background(),
		MethodRuntimeGetState,
		nil,
	)
	var rpcErr *Error
	if !errors.As(err, &rpcErr) ||
		rpcErr.Code != "not_found" ||
		rpcErr.Message != "missing" ||
		rpcErr.Data == nil {
		t.Fatalf("unexpected remote error: %#v", err)
	}
}

func TestClientEnforcesRequestResponseAndTimeLimits(t *testing.T) {
	client, err := NewClient(ClientConfig{
		Address:         "127.0.0.1:1",
		Timeout:         time.Second,
		MaxRequestBytes: 256,
	})
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.CallRaw(
		context.Background(),
		MethodContentValidateDefinition,
		map[string]any{
			"contentId": "x",
			"definition": map[string]any{
				"data": stringsRepeat("x", 300),
			},
		},
	)
	var rpcErr *Error
	if !errors.As(err, &rpcErr) || rpcErr.Code != CodeRequestTooLarge {
		t.Fatalf("request limit error = %#v", err)
	}

	address := startOneShotWireServer(t, func(request Request) string {
		return fmt.Sprintf(
			`{"id":%d,"result":{"data":"%s"}}`,
			request.ID,
			stringsRepeat("x", 300),
		)
	})
	client, err = NewClient(ClientConfig{
		Address:          address,
		Timeout:          time.Second,
		MaxResponseBytes: 256,
	})
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.CallRaw(
		context.Background(),
		MethodRuntimeGetState,
		nil,
	)
	if !errors.As(err, &rpcErr) || rpcErr.Code != CodeResponseTooLarge {
		t.Fatalf("response limit error = %#v", err)
	}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	go func() {
		connection, err := listener.Accept()
		if err == nil {
			defer connection.Close()
			time.Sleep(250 * time.Millisecond)
		}
	}()
	client, err = NewClient(ClientConfig{
		Address: listener.Addr().String(),
		Timeout: 40 * time.Millisecond,
	})
	if err != nil {
		t.Fatal(err)
	}
	started := time.Now()
	_, err = client.CallRaw(
		context.Background(),
		MethodRuntimeGetState,
		nil,
	)
	if err == nil {
		t.Fatal("client did not enforce its timeout")
	}
	if time.Since(started) > 200*time.Millisecond {
		t.Fatalf("client timeout took too long: %v", err)
	}
}

func startOneShotWireServer(
	t *testing.T,
	response func(Request) string,
) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		defer listener.Close()
		connection, err := listener.Accept()
		if err != nil {
			return
		}
		defer connection.Close()
		line, err := bufio.NewReader(connection).ReadBytes('\n')
		if err != nil {
			return
		}
		var request Request
		if err := json.Unmarshal(line, &request); err != nil {
			return
		}
		_, _ = fmt.Fprintln(connection, response(request))
	}()
	t.Cleanup(func() {
		_ = listener.Close()
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Error("one-shot wire server did not stop")
		}
	})
	return listener.Addr().String()
}

func stringsContainsFold(value, substring string) bool {
	return strings.Contains(
		strings.ToLower(value),
		strings.ToLower(substring),
	)
}

func stringsRepeat(value string, count int) string {
	return strings.Repeat(value, count)
}
