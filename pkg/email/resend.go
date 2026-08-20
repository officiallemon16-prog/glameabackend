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
		Subject: "Your GLAMEA verification code",
		Html: fmt.Sprintf(`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Your GLAMEA verification code</title>
</head>
<body style="margin:0;padding:0;background-color:#FAF9F7;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#FAF9F7;padding:40px 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(107,26,43,0.10);">
          <tr>
            <td style="background-color:#6B1A2B;background:linear-gradient(135deg,#6B1A2B 0%,#8A2438 100%);padding:38px 32px;text-align:center;">
              <div style="font-family:Georgia,'Times New Roman',serif;font-size:30px;letter-spacing:7px;font-weight:700;color:#ffffff;">GLAMEA</div>
              <div style="margin-top:10px;font-size:11px;letter-spacing:3px;text-transform:uppercase;color:#EAD8D2;">Beauty, booked beautifully</div>
            </td>
          </tr>
          <tr>
            <td style="padding:38px 32px 12px;">
              <p style="margin:0 0 14px;font-size:16px;color:#1C1917;font-weight:600;">Hi there,</p>
              <p style="margin:0 0 26px;font-size:15px;line-height:25px;color:#57534E;">Use the verification code below to confirm your email and step into <strong>GLAMEA</strong>. We're thrilled to have you join our community of beauty professionals and the clients who love them.</p>
              <div style="background-color:#EAD8D2;border:1px solid #C98F86;border-radius:14px;padding:26px;text-align:center;">
                <div style="font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#8A2438;margin-bottom:10px;">Your verification code</div>
                <div style="font-size:38px;font-weight:700;letter-spacing:12px;color:#6B1A2B;font-family:'Courier New',Courier,monospace;">%s</div>
              </div>
              <p style="margin:26px 0 0;font-size:13px;line-height:21px;color:#78716C;">This code expires in <strong>5 minutes</strong>. For your security, never share it with anyone &mdash; GLAMEA will never ask for it.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:22px 32px 34px;border-top:1px solid #F2F0ED;">
              <p style="margin:0;font-size:12px;line-height:19px;color:#78716C;">You received this email because you signed up for GLAMEA. If this wasn't you, you can safely ignore it.</p>
              <p style="margin:14px 0 0;font-size:12px;letter-spacing:1px;color:#C98F86;">&#9829; GLAMEA &mdash; Beauty, booked beautifully</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`, html.EscapeString(code)),
	}
	_, err := s.client.Emails.Send(params)
	if err != nil {
		return httpx.NewError(http.StatusBadGateway, "email_delivery_failed", fmt.Sprintf("failed to send verification email: %v", err))
	}
	return nil
}
