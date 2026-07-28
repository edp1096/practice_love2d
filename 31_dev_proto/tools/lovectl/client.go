package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"sync/atomic"
	"time"
)

type protocolClient struct {
	host    string
	port    int
	timeout time.Duration
	nextID  atomic.Int64
}

type protocolRequest struct {
	ID     int64          `json:"id"`
	Method string         `json:"method"`
	Params map[string]any `json:"params"`
}

type protocolResponse struct {
	ID     int64           `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  *protocolError  `json:"error"`
}

type protocolError struct {
	Message string `json:"message"`
}

func newProtocolClient(host string, port int, timeout time.Duration) *protocolClient {
	client := &protocolClient{
		host:    host,
		port:    port,
		timeout: timeout,
	}
	client.nextID.Store(0)
	return client
}

func (client *protocolClient) call(
	method string,
	params map[string]any,
	target any,
) error {
	if params == nil {
		params = map[string]any{}
	}

	ctx, cancel := context.WithTimeout(context.Background(), client.timeout)
	defer cancel()

	address := net.JoinHostPort(client.host, fmt.Sprintf("%d", client.port))
	connection, err := (&net.Dialer{}).DialContext(ctx, "tcp", address)
	if err != nil {
		return fmt.Errorf("connect to debug bridge: %w", err)
	}
	defer connection.Close()

	deadline, ok := ctx.Deadline()
	if ok {
		if err := connection.SetDeadline(deadline); err != nil {
			return fmt.Errorf("set protocol deadline: %w", err)
		}
	}

	request := protocolRequest{
		ID:     client.nextID.Add(1),
		Method: method,
		Params: params,
	}
	if err := json.NewEncoder(connection).Encode(request); err != nil {
		return fmt.Errorf("send %s: %w", method, err)
	}

	line, err := bufio.NewReader(connection).ReadBytes('\n')
	if err != nil {
		return fmt.Errorf("read %s response: %w", method, err)
	}

	var response protocolResponse
	if err := json.Unmarshal(line, &response); err != nil {
		return fmt.Errorf("decode %s response: %w", method, err)
	}
	if response.ID != request.ID {
		return fmt.Errorf(
			"protocol response ID mismatch: sent %d, received %d",
			request.ID,
			response.ID,
		)
	}
	if response.Error != nil {
		return errors.New(response.Error.Message)
	}
	if target == nil {
		return nil
	}
	if len(response.Result) == 0 {
		return fmt.Errorf("%s response has no result", method)
	}
	if err := json.Unmarshal(response.Result, target); err != nil {
		return fmt.Errorf("decode %s result: %w", method, err)
	}
	return nil
}

func (client *protocolClient) rawCall(
	method string,
	params map[string]any,
) (json.RawMessage, error) {
	var result json.RawMessage
	err := client.call(method, params, &result)
	return result, err
}

func printJSON(value any) error {
	encoded, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(encoded))
	return nil
}
