package protocol

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	defaultReadTimeout    = 5 * time.Second
	defaultWriteTimeout   = 5 * time.Second
	defaultBackendTimeout = 15 * time.Second
	defaultMaxConnections = 16
)

type Config struct {
	Address          string
	ReadTimeout      time.Duration
	WriteTimeout     time.Duration
	BackendTimeout   time.Duration
	MaxRequestBytes  int
	MaxParamsBytes   int
	MaxResponseBytes int
	MaxConnections   int
	FixedStepSeconds float64
	// AuthToken optionally requires a shared secret on every request. Set it
	// for shared-user hosts; it is never returned in protocol responses.
	AuthToken string
}

func DefaultConfig() Config {
	return Config{
		Address:          DefaultAddress,
		ReadTimeout:      defaultReadTimeout,
		WriteTimeout:     defaultWriteTimeout,
		BackendTimeout:   defaultBackendTimeout,
		MaxRequestBytes:  DefaultMaxRequestBytes,
		MaxParamsBytes:   DefaultMaxParamsBytes,
		MaxResponseBytes: DefaultMaxResponseBytes,
		MaxConnections:   defaultMaxConnections,
		FixedStepSeconds: 1.0 / 60.0,
	}
}

func normalizeConfig(config Config) (Config, error) {
	defaults := DefaultConfig()
	if config.Address == "" {
		config.Address = defaults.Address
	}
	if config.ReadTimeout == 0 {
		config.ReadTimeout = defaults.ReadTimeout
	}
	if config.WriteTimeout == 0 {
		config.WriteTimeout = defaults.WriteTimeout
	}
	if config.BackendTimeout == 0 {
		config.BackendTimeout = defaults.BackendTimeout
	}
	if config.MaxRequestBytes == 0 {
		config.MaxRequestBytes = defaults.MaxRequestBytes
	}
	if config.MaxParamsBytes == 0 {
		config.MaxParamsBytes = defaults.MaxParamsBytes
	}
	if config.MaxResponseBytes == 0 {
		config.MaxResponseBytes = defaults.MaxResponseBytes
	}
	if config.MaxConnections == 0 {
		config.MaxConnections = defaults.MaxConnections
	}
	if config.FixedStepSeconds == 0 {
		config.FixedStepSeconds = defaults.FixedStepSeconds
	}

	if config.ReadTimeout < 0 ||
		config.WriteTimeout < 0 ||
		config.BackendTimeout < 0 {
		return Config{}, errors.New("protocol timeouts must be positive")
	}
	if config.MaxRequestBytes < 256 {
		return Config{}, errors.New("MaxRequestBytes must be at least 256")
	}
	if config.MaxParamsBytes < 2 ||
		config.MaxParamsBytes > config.MaxRequestBytes {
		return Config{}, errors.New(
			"MaxParamsBytes must be between 2 and MaxRequestBytes",
		)
	}
	if config.MaxResponseBytes < 256 {
		return Config{}, errors.New("MaxResponseBytes must be at least 256")
	}
	if config.MaxConnections < 1 || config.MaxConnections > 1024 {
		return Config{}, errors.New(
			"MaxConnections must be between 1 and 1024",
		)
	}
	if len(config.AuthToken) > maxTokenBytes {
		return Config{}, fmt.Errorf(
			"AuthToken must be at most %d bytes",
			maxTokenBytes,
		)
	}
	if math.IsNaN(config.FixedStepSeconds) ||
		math.IsInf(config.FixedStepSeconds, 0) ||
		config.FixedStepSeconds <= 0 {
		return Config{}, errors.New(
			"FixedStepSeconds must be a positive finite number",
		)
	}
	if err := validateLoopbackAddress(config.Address); err != nil {
		return Config{}, err
	}
	return config, nil
}

// Server exposes a Backend over line-delimited JSON on a loopback TCP socket.
// It is safe for concurrent connections.
type Server struct {
	backend Backend
	config  Config

	backendGate sync.RWMutex
	connections sync.Mutex
	active      map[net.Conn]struct{}
}

func NewServer(backend Backend, config Config) (*Server, error) {
	if backend == nil {
		return nil, errors.New("protocol backend is required")
	}
	normalized, err := normalizeConfig(config)
	if err != nil {
		return nil, err
	}
	return &Server{
		backend: backend,
		config:  normalized,
		active:  make(map[net.Conn]struct{}),
	}, nil
}

func (server *Server) Config() Config {
	return server.config
}

// ListenAndServe owns its loopback listener until ctx is canceled or a fatal
// accept error occurs.
func (server *Server) ListenAndServe(ctx context.Context) error {
	if ctx == nil {
		return errors.New("protocol context is required")
	}
	listener, err := (&net.ListenConfig{}).Listen(
		ctx,
		"tcp",
		server.config.Address,
	)
	if err != nil {
		return fmt.Errorf("listen for debug protocol: %w", err)
	}
	return server.Serve(ctx, listener)
}

// Serve accepts loopback clients from listener. Serve takes ownership of the
// listener and closes active connections during shutdown.
func (server *Server) Serve(ctx context.Context, listener net.Listener) error {
	if ctx == nil {
		return errors.New("protocol context is required")
	}
	if listener == nil {
		return errors.New("protocol listener is required")
	}
	if err := validateLoopbackListener(listener); err != nil {
		_ = listener.Close()
		return err
	}

	limit := make(chan struct{}, server.config.MaxConnections)
	var handlers sync.WaitGroup
	shutdownDone := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			_ = listener.Close()
			server.closeConnections()
		case <-shutdownDone:
		}
	}()
	defer func() {
		close(shutdownDone)
		_ = listener.Close()
		server.closeConnections()
		handlers.Wait()
	}()

	for {
		connection, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil || errors.Is(err, net.ErrClosed) {
				return nil
			}
			var temporary interface{ Temporary() bool }
			if errors.As(err, &temporary) && temporary.Temporary() {
				continue
			}
			return fmt.Errorf("accept debug connection: %w", err)
		}
		if !remoteIsLoopback(connection.RemoteAddr()) {
			_ = connection.Close()
			continue
		}
		select {
		case limit <- struct{}{}:
		default:
			_ = connection.Close()
			continue
		}

		server.addConnection(connection)
		handlers.Add(1)
		go func() {
			defer handlers.Done()
			defer func() { <-limit }()
			defer server.removeConnection(connection)
			defer connection.Close()
			server.serveConnection(ctx, connection)
		}()
	}
}

func (server *Server) serveConnection(
	ctx context.Context,
	connection net.Conn,
) {
	readerSize := server.config.MaxRequestBytes
	if readerSize > 64<<10 {
		readerSize = 64 << 10
	}
	reader := bufio.NewReaderSize(connection, readerSize)

	for {
		if err := connection.SetReadDeadline(
			time.Now().Add(server.config.ReadTimeout),
		); err != nil {
			return
		}
		line, err := readLimitedLine(reader, server.config.MaxRequestBytes)
		if err != nil {
			if errors.Is(err, errLineTooLarge) {
				_ = server.writeError(
					connection,
					0,
					rpcError(
						CodeRequestTooLarge,
						"request line exceeds the configured byte limit",
					),
				)
			}
			return
		}
		if len(bytes.TrimSpace(line)) == 0 {
			if err := server.writeError(
				connection,
				0,
				rpcError(CodeInvalidRequest, "request line is empty"),
			); err != nil {
				return
			}
			continue
		}

		response := server.handleRequest(ctx, line)
		if err := server.writeResponse(connection, response); err != nil {
			return
		}
		if response.Error == nil && response.Method != "" {
			server.notifyResponseWritten(response.Method)
		}
	}
}

func (server *Server) handleRequest(
	parent context.Context,
	line []byte,
) (response Response) {
	request, requestErr := decodeRequest(line, server.config.MaxParamsBytes)
	response.ID = request.ID
	if requestErr != nil {
		response.Error = requestErr
		return response
	}
	if server.config.AuthToken != "" &&
		!tokensEqual(request.Token, server.config.AuthToken) {
		response.Error = rpcError(
			CodeUnauthorized,
			"invalid or missing authentication token",
		)
		return response
	}

	defer func() {
		if recovered := recover(); recovered != nil {
			response = Response{
				ID: request.ID,
				Error: rpcError(
					CodeInternal,
					"protocol backend panicked",
				),
			}
		}
	}()

	call, paramsErr := parseCall(request, server.config.FixedStepSeconds)
	if paramsErr != nil {
		response.Error = paramsErr
		return response
	}
	response.Method = call.Method
	switch call.Method {
	case MethodRuntimePing:
		response.Result = mustMarshalRaw(map[string]any{
			"pong":     true,
			"protocol": Version,
			"transport": map[string]any{
				"loopback_only": true,
				"framing":       "ndjson",
				"authenticated": server.config.AuthToken != "",
			},
		})
		return response
	case MethodRuntimeGetProtocol:
		response.Result = mustMarshalRaw(map[string]any{
			"version": Version,
			"methods": Methods(),
			"limits": map[string]int{
				"request_bytes":  server.config.MaxRequestBytes,
				"params_bytes":   server.config.MaxParamsBytes,
				"response_bytes": server.config.MaxResponseBytes,
			},
			"fixed_step_seconds":      server.config.FixedStepSeconds,
			"compatibility_aliases":   CompatibilityAliases(),
			"authentication_required": server.config.AuthToken != "",
		})
		return response
	}

	ctx, cancel := context.WithTimeout(
		parent,
		server.config.BackendTimeout,
	)
	defer cancel()

	encodedResult, backendErr := server.callBackend(ctx, call)
	if backendErr != nil {
		response.Error = backendErr
		return response
	}
	response.Result = encodedResult
	return response
}

func (server *Server) notifyResponseWritten(method string) {
	observer, ok := server.backend.(ResponseObserver)
	if !ok {
		return
	}
	defer func() {
		_ = recover()
	}()
	observer.ProtocolResponseWritten(method)
}

func (server *Server) writeError(
	connection net.Conn,
	id uint64,
	err *Error,
) error {
	return server.writeResponse(connection, Response{ID: id, Error: err})
}

func (server *Server) writeResponse(
	connection net.Conn,
	response Response,
) error {
	encoded, err := json.Marshal(response)
	if err != nil {
		encoded, _ = json.Marshal(Response{
			ID: response.ID,
			Error: rpcError(
				CodeInternal,
				"could not encode protocol response",
			),
		})
	}
	if len(encoded)+1 > server.config.MaxResponseBytes {
		encoded, _ = json.Marshal(Response{
			ID: response.ID,
			Error: rpcError(
				CodeResponseTooLarge,
				"response exceeds the configured byte limit",
			),
		})
	}
	encoded = append(encoded, '\n')
	if err := connection.SetWriteDeadline(
		time.Now().Add(server.config.WriteTimeout),
	); err != nil {
		return err
	}
	return writeAll(connection, encoded)
}

func (server *Server) callBackend(
	ctx context.Context,
	call Call,
) (json.RawMessage, *Error) {
	if call.Mutating() {
		server.backendGate.Lock()
		defer server.backendGate.Unlock()
	} else {
		server.backendGate.RLock()
		defer server.backendGate.RUnlock()
	}
	result, err := server.backend.Call(ctx, call)
	if err != nil {
		return nil, detachBackendError(ctx, err)
	}
	if result == nil {
		result = map[string]any{}
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		return nil, rpcError(
			CodeInternal,
			"backend result is not valid JSON",
		)
	}
	return encoded, nil
}

func detachBackendError(ctx context.Context, err error) *Error {
	var typed *Error
	if errors.As(err, &typed) {
		detached := &Error{
			Code:    typed.Code,
			Message: typed.Message,
		}
		if detached.Code == "" {
			detached.Code = CodeBackend
		}
		if typed.Data != nil {
			encoded, encodeErr := json.Marshal(typed.Data)
			if encodeErr != nil {
				return rpcError(
					CodeInternal,
					"backend error data is not valid JSON",
				)
			}
			detached.Data = json.RawMessage(encoded)
		}
		return detached
	}
	if errors.Is(err, context.DeadlineExceeded) ||
		errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return rpcError(CodeTimeout, "backend operation timed out")
	}
	return rpcError(CodeBackend, err.Error())
}

func (server *Server) addConnection(connection net.Conn) {
	server.connections.Lock()
	server.active[connection] = struct{}{}
	server.connections.Unlock()
}

func (server *Server) removeConnection(connection net.Conn) {
	server.connections.Lock()
	delete(server.active, connection)
	server.connections.Unlock()
}

func (server *Server) closeConnections() {
	server.connections.Lock()
	defer server.connections.Unlock()
	for connection := range server.active {
		_ = connection.Close()
	}
}

var errLineTooLarge = errors.New("line exceeds limit")

func readLimitedLine(reader *bufio.Reader, limit int) ([]byte, error) {
	line := make([]byte, 0, min(limit, 4096))
	for {
		fragment, err := reader.ReadSlice('\n')
		if len(line)+len(fragment) > limit {
			return nil, errLineTooLarge
		}
		line = append(line, fragment...)
		switch {
		case err == nil:
			line = line[:len(line)-1]
			line = bytes.TrimSuffix(line, []byte{'\r'})
			return line, nil
		case errors.Is(err, bufio.ErrBufferFull):
			continue
		case errors.Is(err, io.EOF) && len(line) > 0:
			// A request is not complete until its newline delimiter arrives.
			return nil, io.ErrUnexpectedEOF
		default:
			return nil, err
		}
	}
}

func validateLoopbackAddress(address string) error {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return fmt.Errorf("invalid protocol address %q: %w", address, err)
	}
	if port == "" {
		return errors.New("protocol address is missing a port")
	}
	if parsed, err := strconv.ParseUint(port, 10, 16); err != nil ||
		parsed > 65535 {
		return fmt.Errorf("invalid protocol port %q", port)
	}
	trimmedHost := strings.TrimSpace(host)
	if strings.EqualFold(trimmedHost, "localhost") {
		return nil
	}
	ip := net.ParseIP(trimmedHost)
	if ip == nil || !ip.IsLoopback() {
		return fmt.Errorf(
			"debug protocol must bind to a loopback address, got %q",
			host,
		)
	}
	return nil
}

func validateLoopbackListener(listener net.Listener) error {
	if listener == nil {
		return errors.New("protocol listener is required")
	}
	address := listener.Addr()
	tcpAddress, ok := address.(*net.TCPAddr)
	if ok {
		if tcpAddress.IP == nil || !tcpAddress.IP.IsLoopback() {
			return fmt.Errorf(
				"debug protocol listener is not loopback-only: %s",
				address,
			)
		}
		return nil
	}
	if err := validateLoopbackAddress(address.String()); err != nil {
		return fmt.Errorf("debug protocol listener is not loopback-only: %w", err)
	}
	return nil
}

func remoteIsLoopback(address net.Addr) bool {
	tcpAddress, ok := address.(*net.TCPAddr)
	if ok {
		return tcpAddress.IP != nil && tcpAddress.IP.IsLoopback()
	}
	host, _, err := net.SplitHostPort(address.String())
	if err != nil {
		return false
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func mustMarshalRaw(value any) json.RawMessage {
	encoded, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return encoded
}

func tokensEqual(provided, expected string) bool {
	providedHash := sha256.Sum256([]byte(provided))
	expectedHash := sha256.Sum256([]byte(expected))
	return subtle.ConstantTimeCompare(
		providedHash[:],
		expectedHash[:],
	) == 1
}
