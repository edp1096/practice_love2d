package main

import (
	"bufio"
	"encoding/json"
	"net"
	"strings"
	"testing"
	"time"
)

func TestProtocolClientCall(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	done := make(chan error, 1)
	go func() {
		connection, err := listener.Accept()
		if err != nil {
			done <- err
			return
		}
		defer connection.Close()

		line, err := bufio.NewReader(connection).ReadBytes('\n')
		if err != nil {
			done <- err
			return
		}
		var request protocolRequest
		if err := json.Unmarshal(line, &request); err != nil {
			done <- err
			return
		}
		response := map[string]any{
			"id": request.ID,
			"result": map[string]any{
				"pong": true,
			},
		}
		done <- json.NewEncoder(connection).Encode(response)
	}()

	address := listener.Addr().(*net.TCPAddr)
	client := newProtocolClient("127.0.0.1", address.Port, time.Second)
	var result struct {
		Pong bool `json:"pong"`
	}
	if err := client.call("Runtime.ping", nil, &result); err != nil {
		t.Fatal(err)
	}
	if !result.Pong {
		t.Fatal("expected pong")
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestProtocolClientError(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	go func() {
		connection, acceptError := listener.Accept()
		if acceptError != nil {
			return
		}
		defer connection.Close()
		line, readError := bufio.NewReader(connection).ReadBytes('\n')
		if readError != nil {
			return
		}
		var request protocolRequest
		if json.Unmarshal(line, &request) != nil {
			return
		}
		_ = json.NewEncoder(connection).Encode(map[string]any{
			"id": request.ID,
			"error": map[string]any{
				"message": "denied",
			},
		})
	}()

	address := listener.Addr().(*net.TCPAddr)
	client := newProtocolClient("127.0.0.1", address.Port, time.Second)
	err = client.call("Runtime.eval", nil, &map[string]any{})
	if err == nil || !strings.Contains(err.Error(), "denied") {
		t.Fatalf("expected protocol error, got %v", err)
	}
}
