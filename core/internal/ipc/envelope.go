package ipc

import (
	"encoding/json"
	"errors"
	"fmt"
)

type Request struct {
	ID     string          `json:"id"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params,omitempty"`
}

type Response struct {
	ID     string      `json:"id"`
	OK     bool        `json:"ok"`
	Result any         `json:"result,omitempty"`
	Error  *ErrorShape `json:"error,omitempty"`
}

type ErrorShape struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type Error struct {
	Code    string
	Message string
}

func (e *Error) Error() string {
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

func NewError(code, message string) *Error {
	return &Error{Code: code, Message: message}
}

func AsError(err error, target **Error) bool {
	return errors.As(err, target)
}

func DecodeRequest(data []byte) (Request, error) {
	var req Request
	if err := json.Unmarshal(data, &req); err != nil {
		return Request{}, NewError("invalid_json", err.Error())
	}
	if req.ID == "" {
		return Request{}, NewError("invalid_request", "Request id is required")
	}
	if req.Method == "" {
		return Request{}, NewError("invalid_request", "Request method is required")
	}
	if len(req.Params) == 0 {
		req.Params = json.RawMessage(`{}`)
	}
	return req, nil
}

func SuccessResponse(id string, result any) Response {
	return Response{
		ID:     id,
		OK:     true,
		Result: result,
	}
}

func ErrorResponse(id string, err error) Response {
	ipcErr := NewError("internal_error", err.Error())
	AsError(err, &ipcErr)

	return Response{
		ID: id,
		OK: false,
		Error: &ErrorShape{
			Code:    ipcErr.Code,
			Message: ipcErr.Message,
		},
	}
}
