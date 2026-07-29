// Package protocol implements the loopback debug bridge shared by the
// Ebitengine runtime and recreatectl.
package protocol

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
)

const (
	// Version is the wire protocol version required by the Ebitengine spike.
	// This is a deliberately narrower contract than 32_recreate's protocol:
	// only the methods returned by Methods are supported.
	Version = 8

	DefaultAddress          = "127.0.0.1:19832"
	DefaultMaxRequestBytes  = 1 << 20
	DefaultMaxParamsBytes   = 768 << 10
	DefaultMaxResponseBytes = 32 << 20
)

const (
	MethodRuntimePing               = "Runtime.ping"
	MethodRuntimeGetProtocol        = "Runtime.getProtocol"
	MethodRuntimeGetState           = "Runtime.getState"
	MethodContentGetGraph           = "Content.getGraph"
	MethodContentGetDefinition      = "Content.getDefinition"
	MethodContentValidateDefinition = "Content.validateDefinition"
	MethodWorldGetSnapshot          = "World.getSnapshot"
	MethodWorldSetWall              = "World.setWall"
	MethodEntitySetPosition         = "Entity.setPosition"
	MethodEntitySetHealth           = "Entity.setHealth"
	MethodEntityRequestAbility      = "Entity.requestAbility"
	MethodInputAction               = "Input.action"
	MethodEmulationSetPaused        = "Emulation.setPaused"
	MethodEmulationStep             = "Emulation.step"
	MethodPageCaptureScreenshot     = "Page.captureScreenshot"
	MethodAppReloadContent          = "App.reloadContent"
	MethodAppStartNewGame           = "App.startNewGame"
	MethodAppSave                   = "App.save"
	MethodAppLoad                   = "App.load"
	MethodAppQuit                   = "App.quit"

	// Protocol-v8 compatibility aliases are normalized before Backend sees
	// them, preserving the existing controller's save and emulation commands.
	MethodLegacyTestSetPaused = "Test.setPaused"
	MethodLegacyTestStep      = "Test.step"
	MethodLegacySaveWrite     = "Save.write"
	MethodLegacySaveLoad      = "Save.load"
)

var methods = []string{
	MethodRuntimePing,
	MethodRuntimeGetProtocol,
	MethodRuntimeGetState,
	MethodContentGetGraph,
	MethodContentGetDefinition,
	MethodContentValidateDefinition,
	MethodWorldGetSnapshot,
	MethodWorldSetWall,
	MethodEntitySetPosition,
	MethodEntitySetHealth,
	MethodEntityRequestAbility,
	MethodInputAction,
	MethodEmulationSetPaused,
	MethodEmulationStep,
	MethodPageCaptureScreenshot,
	MethodAppReloadContent,
	MethodAppStartNewGame,
	MethodAppSave,
	MethodAppLoad,
	MethodAppQuit,
	MethodLegacyTestSetPaused,
	MethodLegacyTestStep,
	MethodLegacySaveWrite,
	MethodLegacySaveLoad,
}

// Methods returns the stable protocol method order advertised on the wire.
func Methods() []string {
	return slices.Clone(methods)
}

// Backend is the only runtime integration point. The protocol package validates
// and normalizes every request before delivering a typed Call. Implementations
// commonly enqueue the call onto the Ebitengine update goroutine and wait for
// either its result or ctx cancellation. Implementations must honor ctx and
// return promptly when it is canceled; graceful server shutdown depends on it.
type Backend interface {
	Call(ctx context.Context, call Call) (any, error)
}

// ResponseObserver is an optional backend hook invoked only after a successful
// response write. Process-exit methods use it so the connection is not canceled
// before the caller receives its acknowledgement.
type ResponseObserver interface {
	ProtocolResponseWritten(method string)
}

// BackendFunc adapts a function into a Backend.
type BackendFunc func(context.Context, Call) (any, error)

func (fn BackendFunc) Call(ctx context.Context, call Call) (any, error) {
	return fn(ctx, call)
}

// Call is a validated backend operation. Params is one of the exported
// parameter structs below; methods without parameters receive EmptyParams.
type Call struct {
	Method string
	Params any
}

// Mutating reports whether this call changes runtime, world, save, or process
// state. Server serializes all such backend calls across all connections.
func (call Call) Mutating() bool {
	return IsMutating(call.Method)
}

// IsMutating classifies protocol operations which must never overlap.
func IsMutating(method string) bool {
	switch method {
	case MethodWorldSetWall,
		MethodEntitySetPosition,
		MethodEntitySetHealth,
		MethodEntityRequestAbility,
		MethodInputAction,
		MethodEmulationSetPaused,
		MethodEmulationStep,
		MethodAppReloadContent,
		MethodAppStartNewGame,
		MethodAppSave,
		MethodAppLoad,
		MethodAppQuit,
		MethodLegacyTestSetPaused,
		MethodLegacyTestStep,
		MethodLegacySaveWrite,
		MethodLegacySaveLoad:
		return true
	default:
		return false
	}
}

// CanonicalMethod maps accepted protocol-v8 aliases onto Backend method names.
func CanonicalMethod(method string) string {
	switch method {
	case MethodLegacyTestSetPaused:
		return MethodEmulationSetPaused
	case MethodLegacyTestStep:
		return MethodEmulationStep
	case MethodLegacySaveWrite:
		return MethodAppSave
	case MethodLegacySaveLoad:
		return MethodAppLoad
	default:
		return method
	}
}

// CompatibilityAliases returns old-to-canonical v8 method mappings.
func CompatibilityAliases() map[string]string {
	return map[string]string{
		MethodLegacyTestSetPaused: MethodEmulationSetPaused,
		MethodLegacyTestStep:      MethodEmulationStep,
		MethodLegacySaveWrite:     MethodAppSave,
		MethodLegacySaveLoad:      MethodAppLoad,
	}
}

type EmptyParams struct{}

type ContentIDParams struct {
	ContentID string `json:"contentId"`
}

type ValidateDefinitionParams struct {
	ContentID  string          `json:"contentId"`
	Definition json.RawMessage `json:"definition"`
}

type SetPositionParams struct {
	EntityID string  `json:"entityId"`
	X        float64 `json:"x"`
	Y        float64 `json:"y"`
}

type SetWallParams struct {
	WallID string  `json:"wallId"`
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

type SetHealthParams struct {
	EntityID string  `json:"entityId"`
	Value    float64 `json:"value"`
}

type RequestAbilityParams struct {
	EntityID  string `json:"entityId"`
	AbilityID string `json:"abilityId"`
}

type InputActionParams struct {
	Action string  `json:"action"`
	Value  float64 `json:"value"`
	Frames int     `json:"frames"`
}

type SetPausedParams struct {
	Enabled bool `json:"enabled"`
}

type StepParams struct {
	Frames int      `json:"frames"`
	DT     *float64 `json:"dt,omitempty"`
}

type SaveSlotParams struct {
	Slot string `json:"slot"`
}

// Request and Response are the newline-delimited wire envelopes.
type Request struct {
	ID     uint64          `json:"id"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
	Token  string          `json:"token,omitempty"`
}

type Response struct {
	ID     uint64          `json:"id"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *Error          `json:"error,omitempty"`
	Method string          `json:"-"`
}

const (
	CodeParseError       = "parse_error"
	CodeInvalidRequest   = "invalid_request"
	CodeInvalidParams    = "invalid_params"
	CodeMethodNotFound   = "method_not_found"
	CodeRequestTooLarge  = "request_too_large"
	CodeResponseTooLarge = "response_too_large"
	CodeUnauthorized     = "unauthorized"
	CodeBackend          = "backend_error"
	CodeTimeout          = "timeout"
	CodeInternal         = "internal_error"
)

// Error is both the structured wire error and the error returned by Client.
// Data must be JSON-marshalable when it is set.
type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

func (err *Error) Error() string {
	if err == nil {
		return ""
	}
	if err.Code == "" {
		return err.Message
	}
	return fmt.Sprintf("%s: %s", err.Code, err.Message)
}

func rpcError(code, message string) *Error {
	return &Error{Code: code, Message: message}
}
