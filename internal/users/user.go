package users

import "time"

const (
	RoleCustomer     = "CUSTOMER"
	RoleProfessional = "PROFESSIONAL"
	RoleAdmin        = "ADMIN"
)

const (
	StatusActive    = "ACTIVE"
	StatusSuspended = "SUSPENDED"
	StatusDisabled  = "DISABLED"
)

type User struct {
	ID            string     `json:"id"`
	Email         *string    `json:"email"`
	Phone         *string    `json:"phone"`
	FirstName     string     `json:"first_name"`
	LastName      string     `json:"last_name"`
	AvatarMediaID *string    `json:"avatar_media_id"`
	Role          string     `json:"role"`
	Status        string     `json:"status"`
	EmailVerified bool       `json:"email_verified"`
	PhoneVerified bool       `json:"phone_verified"`
	LastLoginAt   *time.Time `json:"last_login_at"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

func (u *User) FullName() string {
	name := u.FirstName
	if u.LastName != "" {
		if name != "" {
			name += " "
		}
		name += u.LastName
	}
	return name
}
