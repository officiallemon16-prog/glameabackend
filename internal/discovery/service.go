package discovery

import (
	"context"

	"github.com/glamea/glamea-backend/internal/categories"
	"github.com/glamea/glamea-backend/internal/deals"
	"github.com/glamea/glamea-backend/internal/professionals"
	"github.com/glamea/glamea-backend/internal/services"
)

type Service struct {
	proStore  *professionals.Store
	svcStore  *services.Store
	catStore  *categories.Store
	dealStore *deals.Store
}

func NewService(proStore *professionals.Store, svcStore *services.Store, catStore *categories.Store, dealStore *deals.Store) *Service {
	return &Service{
		proStore:  proStore,
		svcStore:  svcStore,
		catStore:  catStore,
		dealStore: dealStore,
	}
}

type Home struct {
	Categories    []*categories.Category        `json:"categories"`
	Professionals []*professionals.Professional `json:"professionals"`
	Services      []*services.Service           `json:"services"`
	Deals         []*deals.Deal                 `json:"deals"`
}

func (s *Service) Home(ctx context.Context, limit int) (*Home, error) {
	if limit <= 0 || limit > 20 {
		limit = 10
	}
	home := &Home{}

	cats, err := s.catStore.List(ctx, false)
	if err != nil {
		return nil, err
	}
	home.Categories = cats

	pros, _, err := s.proStore.List(ctx, professionals.ListFilter{Limit: limit, Offset: 0, Sort: "rating"})
	if err != nil {
		return nil, err
	}
	home.Professionals = pros

	svcs, _, err := s.svcStore.List(ctx, services.ListFilter{Limit: limit, Offset: 0})
	if err != nil {
		return nil, err
	}
	home.Services = svcs

	active, _, err := s.dealStore.ListActive(ctx, limit, 0)
	if err != nil {
		return nil, err
	}
	home.Deals = active

	return home, nil
}

type SearchInput struct {
	Query           string
	CategoryID      string
	City            string
	VerifiedOnly    bool
	HomeServiceOnly bool
	Sort            string
	Limit           int
	Offset          int
}

type SearchResult struct {
	Professionals []*professionals.Professional `json:"professionals"`
	Services      []*services.Service           `json:"services"`
	Total         int64                         `json:"total"`
}

func (s *Service) Search(ctx context.Context, in SearchInput) (*SearchResult, error) {
	if in.Limit <= 0 || in.Limit > 100 {
		in.Limit = 20
	}
	pros, _, err := s.proStore.List(ctx, professionals.ListFilter{
		Query:           in.Query,
		CategoryID:      in.CategoryID,
		City:            in.City,
		VerifiedOnly:    in.VerifiedOnly,
		HomeServiceOnly: in.HomeServiceOnly,
		Sort:            in.Sort,
		Limit:           in.Limit,
		Offset:          in.Offset,
	})
	if err != nil {
		return nil, err
	}
	svcs, _, err := s.svcStore.List(ctx, services.ListFilter{
		CategoryID: in.CategoryID,
		Limit:      in.Limit,
		Offset:     in.Offset,
	})
	if err != nil {
		return nil, err
	}
	return &SearchResult{
		Professionals: pros,
		Services:      svcs,
		Total:         int64(len(pros)) + int64(len(svcs)),
	}, nil
}

func (s *Service) Professional(ctx context.Context, id string) (*professionals.PublicProfile, error) {
	return s.proStore.PublicProfile(ctx, id)
}

func (s *Service) ServicesForProfessional(ctx context.Context, id string) ([]*services.Service, int64, error) {
	return s.svcStore.List(ctx, services.ListFilter{ProfessionalID: id, Limit: 100, Offset: 0})
}

type CategoryResult struct {
	Category      *categories.Category          `json:"category"`
	Professionals []*professionals.Professional `json:"professionals"`
}

func (s *Service) CategoryBySlug(ctx context.Context, slug string, limit, offset int) (*CategoryResult, error) {
	cat, err := s.catStore.GetBySlug(ctx, slug)
	if err != nil {
		return nil, err
	}
	pros, _, err := s.proStore.List(ctx, professionals.ListFilter{
		CategoryID: cat.ID,
		Sort:       "rating",
		Limit:      limit,
		Offset:     offset,
	})
	if err != nil {
		return nil, err
	}
	return &CategoryResult{Category: cat, Professionals: pros}, nil
}
