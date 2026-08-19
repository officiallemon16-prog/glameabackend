package email

import (
	"fmt"
	"html"
	"net/http"

	"github.com/glamea/glamea-backend/pkg/httpx"
	"github.com/resend/resend-go/v2"
)

type ResendSender struct {
	client *resend.Client
	from   string
}

func NewResendSender(apiKey, from string) *ResendSender {
	if from == "" {
		from = "Glamea <onboarding@resend.dev>"
	}
	return &ResendSender{
		client: resend.NewClient(apiKey),
		from:   from,
	}
}

func (s *ResendSender) SendOTP(to, code string) error {
	params := &resend.SendEmailRequest{
		From:    s.from,
		To:      []string{to},
		Subject: "Your Glamea verification code",
		Html: fmt.Sprintf(`<div style="font-family:sans-serif;max-width:400px;margin:auto;padding:24px">
  <h2 style="color:#6B21A8">Glamea</h2>
  <p>Your verification code is:</p>
  <p style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#1a1a1a;margin:24px 0">%s</p>
  <p style="color:#666;font-size:14px">This code expires in 5 minutes. Do not share it with anyone.</p>
</div>`, html.EscapeString(code)),
	}
	_, err := s.client.Emails.Send(params)
	if err != nil {
		return httpx.NewError(http.StatusBadGateway, "email_delivery_failed", fmt.Sprintf("failed to send verification email: %v", err))
	}
	return nil
}
