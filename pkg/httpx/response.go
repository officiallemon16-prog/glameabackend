package httpx

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
)

type Meta struct {
	Page           int    `json:"page,omitempty"`
	PerPage        int    `json:"per_page,omitempty"`
	Total          int64  `json:"total,omitempty"`
	HasMore        bool   `json:"has_more,omitempty"`
	NextCursor     string `json:"next_cursor,omitempty"`
	PreviousCursor string `json:"previous_cursor,omitempty"`
}

type Response struct {
	Data any `json:"data,omitempty"`
	Meta any `json:"meta,omitempty"`
}

type ErrorResponse struct {
	Error ErrorBody `json:"error"`
}

type ErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Field   string `json:"field,omitempty"`
}

type APIError struct {
	Status  int
	Code    string
	Message string
	Field   string
	Err     error
}

func (e *APIError) Error() string {
	if e.Err != nil {
		return e.Message + ": " + e.Err.Error()
	}
	return e.Message
}

func (e *APIError) Unwrap() error { return e.Err }

func NewError(status int, code, message string) *APIError {
	return &APIError{Status: status, Code: code, Message: message}
}

func BadRequest(code, message string) *APIError {
	return NewError(http.StatusBadRequest, code, message)
}

func Unauthorized(code, message string) *APIError {
	return NewError(http.StatusUnauthorized, code, message)
}

func Forbidden(code, message string) *APIError {
	return NewError(http.StatusForbidden, code, message)
}

func NotFound(code, message string) *APIError {
	return NewError(http.StatusNotFound, code, message)
}

func Conflict(code, message string) *APIError {
	return NewError(http.StatusConflict, code, message)
}

func Internal(code, message string) *APIError {
	return NewError(http.StatusInternalServerError, code, message)
}

func ServiceUnavailable(code, message string) *APIError {
	return NewError(http.StatusServiceUnavailable, code, message)
}

func AsAPIError(err error) *APIError {
	var apiErr *APIError
	if errors.As(err, &apiErr) {
		return apiErr
	}
	return Internal("internal_error", "something went wrong")
}

func JSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if body == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(body); err != nil {
		slog.Error("encode response", "error", err)
	}
}

func OK(w http.ResponseWriter, data any) {
	JSON(w, http.StatusOK, Response{Data: data})
}

func Created(w http.ResponseWriter, data any) {
	JSON(w, http.StatusCreated, Response{Data: data})
}

func NoContent(w http.ResponseWriter) {
	w.WriteHeader(http.StatusNoContent)
}

func Fail(w http.ResponseWriter, err error) {
	apiErr := AsAPIError(err)
	body := ErrorResponse{Error: ErrorBody{
		Code:    apiErr.Code,
		Message: apiErr.Message,
		Field:   apiErr.Field,
	}}
	JSON(w, apiErr.Status, body)
}

func Decode(r *http.Request, dst any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return fmt.Errorf("decode request body: %w", err)
	}
	return nil
}
