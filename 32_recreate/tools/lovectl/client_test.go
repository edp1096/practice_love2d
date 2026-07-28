package main

import (
	"bufio"
	"encoding/json"
	"net"
	"testing"
	"time"
)

func TestProtocolClientRoundTrip(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	done := make(chan error, 1)
	go func() {
		connection, acceptErr := listener.Accept()
		if acceptErr != nil {
			done <- acceptErr
			return
		}
		defer connection.Close()

		line, readErr := bufio.NewReader(connection).ReadBytes('\n')
		if readErr != nil {
			done <- readErr
			return
		}
		var request protocolRequest
		if decodeErr := json.Unmarshal(line, &request); decodeErr != nil {
			done <- decodeErr
			return
		}
		response := map[string]any{
			"id": request.ID,
			"result": map[string]any{
				"method": request.Method,
			},
		}
		done <- json.NewEncoder(connection).Encode(response)
	}()

	port := listener.Addr().(*net.TCPAddr).Port
	client := newProtocolClient("127.0.0.1", port, 2*time.Second)
	var result struct {
		Method string `json:"method"`
		Stale  bool   `json:"stale"`
	}
	result.Stale = true
	if err := client.call("Runtime.ping", nil, &result); err != nil {
		t.Fatal(err)
	}
	if result.Method != "Runtime.ping" {
		t.Fatalf("unexpected method: %q", result.Method)
	}
	if result.Stale {
		t.Fatal("response target retained a field omitted by the server")
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}
