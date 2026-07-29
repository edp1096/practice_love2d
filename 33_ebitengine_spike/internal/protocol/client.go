package protocol

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"reflect"
	"sync/atomic"
	"time"
)

type ClientConfig struct {
	Address          string
	Timeout          time.Duration
	MaxRequestBytes  int
	MaxResponseBytes int
	AuthToken        string
}

func DefaultClientConfig() ClientConfig {
	return ClientConfig{
		Address:          DefaultAddress,
		Timeout:          defaultBackendTimeout,
		MaxRequestBytes:  DefaultMaxRequestBytes,
		MaxResponseBytes: DefaultMaxResponseBytes,
	}
}

type Client struct {
	config ClientConfig
	nextID atomic.Uint64
}

func NewClient(config ClientConfig) (*Client, error) {
	defaults := DefaultClientConfig()
	if config.Address == "" {
		config.Address = defaults.Address
	}
	if config.Timeout == 0 {
		config.Timeout = defaults.Timeout
	}
	if config.MaxRequestBytes == 0 {
		config.MaxRequestBytes = defaults.MaxRequestBytes
	}
	if config.MaxResponseBytes == 0 {
		config.MaxResponseBytes = defaults.MaxResponseBytes
	}
	if config.Timeout < 0 {
		return nil, errors.New("client timeout must be positive")
	}
	if config.MaxRequestBytes < 256 {
		return nil, errors.New("MaxRequestBytes must be at least 256")
	}
	if config.MaxResponseBytes < 256 {
		return nil, errors.New("MaxResponseBytes must be at least 256")
	}
	if len(config.AuthToken) > maxTokenBytes {
		return nil, fmt.Errorf(
			"AuthToken must be at most %d bytes",
			maxTokenBytes,
		)
	}
	if err := validateLoopbackAddress(config.Address); err != nil {
		return nil, err
	}
	return &Client{config: config}, nil
}

func (client *Client) Config() ClientConfig {
	return client.config
}

// Call sends one request using a fresh connection and decodes its result into
// target. Request IDs begin at one and increase deterministically per Client.
func (client *Client) Call(
	parent context.Context,
	method string,
	params any,
	target any,
) error {
	result, err := client.CallRaw(parent, method, params)
	if err != nil {
		return err
	}
	if target == nil {
		return nil
	}
	resetTarget(target)
	if err := json.Unmarshal(result, target); err != nil {
		return fmt.Errorf("decode %s result: %w", method, err)
	}
	return nil
}

func (client *Client) CallRaw(
	parent context.Context,
	method string,
	params any,
) (json.RawMessage, error) {
	if parent == nil {
		return nil, errors.New("client context is required")
	}
	if method == "" || len(method) > maxMethodBytes {
		return nil, errors.New("method must be a non-empty bounded string")
	}
	if params == nil {
		params = EmptyParams{}
	}
	encodedParams, err := json.Marshal(params)
	if err != nil {
		return nil, fmt.Errorf("encode %s params: %w", method, err)
	}
	if !isJSONObject(encodedParams) {
		return nil, errors.New("params must encode as a JSON object")
	}
	if err := rejectDuplicateKeys(encodedParams); err != nil {
		return nil, fmt.Errorf("invalid params JSON: %w", err)
	}

	requestID := client.nextID.Add(1)
	request, err := json.Marshal(Request{
		ID:     requestID,
		Method: method,
		Params: encodedParams,
		Token:  client.config.AuthToken,
	})
	if err != nil {
		return nil, fmt.Errorf("encode %s request: %w", method, err)
	}
	request = append(request, '\n')
	if len(request) > client.config.MaxRequestBytes {
		return nil, &Error{
			Code:    CodeRequestTooLarge,
			Message: "request exceeds the configured byte limit",
		}
	}

	ctx, cancel := context.WithTimeout(parent, client.config.Timeout)
	defer cancel()
	connection, err := (&net.Dialer{}).DialContext(
		ctx,
		"tcp",
		client.config.Address,
	)
	if err != nil {
		return nil, fmt.Errorf("connect to debug protocol: %w", err)
	}
	defer connection.Close()
	if !remoteIsLoopback(connection.RemoteAddr()) {
		return nil, fmt.Errorf(
			"debug protocol resolved outside loopback: %s",
			connection.RemoteAddr(),
		)
	}
	if deadline, ok := ctx.Deadline(); ok {
		if err := connection.SetDeadline(deadline); err != nil {
			return nil, fmt.Errorf("set protocol deadline: %w", err)
		}
	}
	if err := writeAll(connection, request); err != nil {
		return nil, fmt.Errorf("send %s: %w", method, err)
	}

	readerSize := client.config.MaxResponseBytes
	if readerSize > 64<<10 {
		readerSize = 64 << 10
	}
	line, err := readLimitedLine(
		bufio.NewReaderSize(connection, readerSize),
		client.config.MaxResponseBytes,
	)
	if errors.Is(err, errLineTooLarge) {
		return nil, &Error{
			Code:    CodeResponseTooLarge,
			Message: "response exceeds the configured byte limit",
		}
	}
	if err != nil {
		return nil, fmt.Errorf("read %s response: %w", method, err)
	}
	if err := rejectDuplicateKeys(line); err != nil {
		return nil, fmt.Errorf("invalid %s response: %w", method, err)
	}
	var response Response
	if err := decodeStrictJSON(line, &response); err != nil {
		return nil, fmt.Errorf("decode %s response: %w", method, err)
	}
	if response.ID != requestID {
		return nil, fmt.Errorf(
			"protocol response ID mismatch: sent %d, received %d",
			requestID,
			response.ID,
		)
	}
	hasResult := len(bytes.TrimSpace(response.Result)) != 0
	if hasResult == (response.Error != nil) {
		return nil, errors.New(
			"protocol response must contain exactly one of result or error",
		)
	}
	if response.Error != nil {
		return nil, response.Error
	}
	return append(json.RawMessage(nil), response.Result...), nil
}

func resetTarget(target any) {
	value := reflect.ValueOf(target)
	if value.Kind() == reflect.Pointer &&
		!value.IsNil() &&
		value.Elem().CanSet() {
		value.Elem().Set(reflect.Zero(value.Elem().Type()))
	}
}

func writeAll(connection net.Conn, data []byte) error {
	for len(data) > 0 {
		written, err := connection.Write(data)
		if err != nil {
			return err
		}
		if written <= 0 {
			return ioErrNoProgress
		}
		data = data[written:]
	}
	return nil
}

var ioErrNoProgress = errors.New("network write made no progress")
