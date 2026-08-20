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

// Emailer is the set of transactional emails GLAMEA sends.
type Emailer interface {
	SendOTP(to, code string) error
	SendWelcome(to, name string) error
	SendBookingConfirmed(to, name, proName, service, when, location string) error
	SendBookingReminder(to, name, when, proName, service string) error
	SendReviewRequest(to, name, proName, service string) error
}

// shell wraps branded GLAMEA body content in the shared email layout
// (oxblood -> rose-gold gradient header, warm blush surface, brand footer).
func (s *ResendSender) shell(title, inner string) string {
	return fmt.Sprintf(`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>%s</title>
</head>
<body style="margin:0;padding:0;background-color:#FAF9F7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%%" cellpadding="0" cellspacing="0" style="background-color:#FAF9F7;padding:40px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(107,26,43,0.10);">
          <tr>
            <td style="background-color:#6B1A2B;background:linear-gradient(135deg,#6B1A2B 0%%,#8A2438 100%%);padding:34px 32px;text-align:center;">
              <div style="font-family:Georgia,'Times New Roman',serif;font-size:30px;letter-spacing:7px;font-weight:700;color:#ffffff;">GLAMEA</div>
              <div style="margin-top:8px;font-size:11px;letter-spacing:3px;text-transform:uppercase;color:#EAD8D2;">Beauty, booked beautifully</div>
            </td>
          </tr>
          <tr>
            <td style="padding:34px 32px;">%s</td>
          </tr>
          <tr>
            <td style="padding:20px 32px 32px;border-top:1px solid #F2F0ED;">
              <p style="margin:0;font-size:12px;line-height:19px;color:#78716C;">You received this email from GLAMEA. If this wasn't you, you can safely ignore it.</p>
              <p style="margin:12px 0 0;font-size:12px;letter-spacing:1px;color:#C98F86;">&#9829; GLAMEA &mdash; Beauty, booked beautifully</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`, title, inner)
}

func (s *ResendSender) send(subject, to, htmlBody string) error {
	_, err := s.client.Emails.Send(&resend.SendEmailRequest{
		From:    s.from,
		To:      []string{to},
		Subject: subject,
		Html:    htmlBody,
	})
	if err != nil {
		return httpx.NewError(http.StatusBadGateway, "email_delivery_failed", fmt.Sprintf("failed to send email: %v", err))
	}
	return nil
}

func (s *ResendSender) SendOTP(to, code string) error {
	inner := fmt.Sprintf(`<p style="margin:0 0 14px;font-size:16px;color:#1C1917;font-weight:600;">Hi there,</p>
<p style="margin:0 0 24px;font-size:15px;line-height:25px;color:#57534E;">Use the verification code below to confirm your email and step into <strong>GLAMEA</strong>. We're thrilled to have you join our community of beauty professionals and the clients who love them.</p>
<div style="background-color:#EAD8D2;border:1px solid #C98F86;border-radius:14px;padding:26px;text-align:center;">
  <div style="font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#8A2438;margin-bottom:10px;">Your verification code</div>
  <div style="font-size:38px;font-weight:700;letter-spacing:12px;color:#6B1A2B;font-family:'Courier New',Courier,monospace;">%s</div>
</div>
<p style="margin:24px 0 0;font-size:13px;line-height:21px;color:#78716C;">This code expires in <strong>5 minutes</strong>. For your security, never share it with anyone &mdash; GLAMEA will never ask for it.</p>`, html.EscapeString(code))
	return s.send("Your GLAMEA verification code", to, s.shell("Your GLAMEA verification code", inner))
}

func (s *ResendSender) SendWelcome(to, name string) error {
	name = html.EscapeString(name)
	inner := fmt.Sprintf(`<p style="margin:0 0 14px;font-size:16px;color:#1C1917;font-weight:600;">Hi %s,</p>
<p style="margin:0 0 18px;font-size:15px;line-height:25px;color:#57534E;">Welcome to <strong>GLAMEA</strong> &mdash; your elegant home for booking trusted beauty professionals. Discover salons, freelancers and studios, book in a tap, and manage every appointment in one beautiful place.</p>
<div style="background:#FAF9F7;border:1px solid #F2F0ED;border-radius:14px;padding:20px 22px;">
  <div style="font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#8A2438;margin-bottom:10px;">Get started</div>
  <p style="margin:0 0 8px;font-size:14px;color:#1C1917;">&#10003; Complete your profile</p>
  <p style="margin:0 0 8px;font-size:14px;color:#1C1917;">&#10003; Browse professionals near you</p>
  <p style="margin:0;font-size:14px;color:#1C1917;">&#10003; Book your first appointment</p>
</div>
<p style="margin:18px 0 0;font-size:13px;line-height:21px;color:#78716C;">Questions? Just reply to this email &mdash; we're here to help.</p>`, name)
	return s.send("Welcome to GLAMEA", to, s.shell("Welcome to GLAMEA", inner))
}

func (s *ResendSender) SendBookingConfirmed(to, name, proName, service, when, location string) error {
	name, proName, service, when, location = html.EscapeString(name), html.EscapeString(proName), html.EscapeString(service), html.EscapeString(when), html.EscapeString(location)
	if location == "" {
		location = "To be confirmed"
	}
	inner := fmt.Sprintf(`<p style="margin:0 0 14px;font-size:16px;color:#1C1917;font-weight:600;">Hi %s,</p>
<p style="margin:0 0 18px;font-size:15px;line-height:25px;color:#57534E;">Great news &mdash; your booking with <strong>%s</strong> is confirmed. We can't wait to see you.</p>
<div style="background:#FAF9F7;border:1px solid #F2F0ED;border-radius:14px;padding:20px 22px;">
  <div style="font-size:13px;color:#78716C;">Service</div>
  <div style="font-size:16px;font-weight:600;color:#1C1917;margin-bottom:12px;">%s</div>
  <div style="font-size:13px;color:#78716C;">When</div>
  <div style="font-size:16px;font-weight:600;color:#1C1917;margin-bottom:12px;">%s</div>
  <div style="font-size:13px;color:#78716C;">Where</div>
  <div style="font-size:16px;font-weight:600;color:#1C1917;">%s</div>
</div>
<p style="margin:18px 0 0;font-size:13px;line-height:21px;color:#78716C;">You'll get a reminder before your appointment. Need to change anything? Manage it anytime in the GLAMEA app.</p>`, name, proName, service, when, location)
	return s.send("Your GLAMEA booking is confirmed", to, s.shell("Your GLAMEA booking is confirmed", inner))
}

func (s *ResendSender) SendBookingReminder(to, name, when, proName, service string) error {
	name, when, proName, service = html.EscapeString(name), html.EscapeString(when), html.EscapeString(proName), html.EscapeString(service)
	inner := fmt.Sprintf(`<p style="margin:0 0 14px;font-size:16px;color:#1C1917;font-weight:600;">Hi %s,</p>
<p style="margin:0 0 18px;font-size:15px;line-height:25px;color:#57534E;">This is a friendly reminder that your appointment with <strong>%s</strong> is coming up soon.</p>
<div style="background:#FAF9F7;border:1px solid #F2F0ED;border-radius:14px;padding:20px 22px;">
  <div style="font-size:13px;color:#78716C;">Service</div>
  <div style="font-size:16px;font-weight:600;color:#1C1917;margin-bottom:12px;">%s</div>
  <div style="font-size:13px;color:#78716C;">When</div>
  <div style="font-size:16px;font-weight:600;color:#1C1917;margin-bottom:12px;">%s</div>
</div>
<p style="margin:18px 0 0;font-size:13px;line-height:21px;color:#78716C;">We look forward to seeing you. Please be ready on time so you can enjoy every minute.</p>`, name, proName, service, when)
	return s.send("Reminder: your GLAMEA appointment is coming up", to, s.shell("Reminder: your GLAMEA appointment is coming up", inner))
}

func (s *ResendSender) SendReviewRequest(to, name, proName, service string) error {
	name, proName, service = html.EscapeString(name), html.EscapeString(proName), html.EscapeString(service)
	inner := fmt.Sprintf(`<p style="margin:0 0 14px;font-size:16px;color:#1C1917;font-weight:600;">Hi %s,</p>
<p style="margin:0 0 18px;font-size:15px;line-height:25px;color:#57534E;">You recently enjoyed <strong>%s</strong> with <strong>%s</strong>. How did it go? Your review helps other clients discover trusted beauty professionals.</p>
<div style="background:#FAF9F7;border:1px solid #F2F0ED;border-radius:14px;padding:20px 22px;text-align:center;">
  <div style="font-size:15px;font-weight:600;color:#6B1A2B;">Open the GLAMEA app to leave a review &#9733;</div>
</div>
<p style="margin:18px 0 0;font-size:13px;line-height:21px;color:#78716C;">It only takes a moment, and it means the world to your professional.</p>`, name, service, proName)
	return s.send("How was your GLAMEA experience?", to, s.shell("How was your GLAMEA experience?", inner))
}
