package ipc

import (
	"encoding/json"
	"testing"
)

func TestDecodeRequestRejectsMissingMethod(t *testing.T) {
	_, err := DecodeRequest([]byte(`{"id":"req_1","params":{}}`))
	if err == nil {
		t.Fatal("expected missing method to be rejected")
	}

	var ipcErr *Error
	if !AsError(err, &ipcErr) {
		t.Fatalf("expected *Error, got %T", err)
	}
	if ipcErr.Code != "invalid_request" {
		t.Fatalf("expected invalid_request, got %q", ipcErr.Code)
	}
}

func TestDecodeRequestKeepsRawParams(t *testing.T) {
	req, err := DecodeRequest([]byte(`{"id":"req_1","method":"health","params":{"verbose":true}}`))
	if err != nil {
		t.Fatalf("DecodeRequest returned error: %v", err)
	}

	if req.ID != "req_1" {
		t.Fatalf("expected request ID req_1, got %q", req.ID)
	}
	if req.Method != "health" {
		t.Fatalf("expected method health, got %q", req.Method)
	}

	var params map[string]bool
	if err := json.Unmarshal(req.Params, &params); err != nil {
		t.Fatalf("params were not valid JSON: %v", err)
	}
	if !params["verbose"] {
		t.Fatal("expected verbose param to be preserved")
	}
}

func TestErrorResponseShape(t *testing.T) {
	resp := ErrorResponse("req_1", NewError("unsupported_method", "Unsupported method: editFile"))

	encoded, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("Marshal returned error: %v", err)
	}

	var decoded struct {
		ID    string `json:"id"`
		OK    bool   `json:"ok"`
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("response was not valid JSON: %v", err)
	}
	if decoded.ID != "req_1" || decoded.OK {
		t.Fatalf("unexpected response envelope: %+v", decoded)
	}
	if decoded.Error.Code != "unsupported_method" {
		t.Fatalf("expected unsupported_method, got %q", decoded.Error.Code)
	}
}
