package cloudinary

import (
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Client struct {
	cloudName    string
	apiKey       string
	apiSecret    string
	uploadFolder string
}

type Config struct {
	CloudName    string
	APIKey       string
	APISecret    string
	UploadFolder string
}

func New(cfg Config) (*Client, error) {
	if cfg.CloudName == "" || cfg.APIKey == "" || cfg.APISecret == "" {
		return &Client{}, nil
	}
	return &Client{
		cloudName:    cfg.CloudName,
		apiKey:       cfg.APIKey,
		apiSecret:    cfg.APISecret,
		uploadFolder: cfg.UploadFolder,
	}, nil
}

func (c *Client) Configured() bool {
	return c.cloudName != "" && c.apiKey != "" && c.apiSecret != ""
}

type Signature struct {
	CloudName    string `json:"cloud_name"`
	APIKey       string `json:"api_key"`
	Timestamp    int64  `json:"timestamp"`
	Signature    string `json:"signature"`
	Folder       string `json:"folder"`
	PublicID     string `json:"public_id,omitempty"`
	ResourceType string `json:"resource_type"`
}

func (c *Client) UploadSignature(folder, publicID, resourceType string) (*Signature, error) {
	if !c.Configured() {
		return nil, fmt.Errorf("cloudinary is not configured")
	}

	timestamp := time.Now().Unix()
	params := map[string]string{
		"timestamp": strconv.FormatInt(timestamp, 10),
	}
	if folder == "" {
		folder = c.uploadFolder
	}
	if folder != "" {
		params["folder"] = folder
	}
	if publicID != "" {
		params["public_id"] = publicID
	}
	if resourceType == "" {
		resourceType = "image"
	}

	keys := make([]string, 0, len(params))
	for k := range params {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, k+"="+params[k])
	}
	toSign := strings.Join(parts, "&") + c.apiSecret

	h := sha1.New()
	h.Write([]byte(toSign))
	signature := hex.EncodeToString(h.Sum(nil))

	return &Signature{
		CloudName:    c.cloudName,
		APIKey:       c.apiKey,
		Timestamp:    timestamp,
		Signature:    signature,
		Folder:       folder,
		PublicID:     publicID,
		ResourceType: resourceType,
	}, nil
}

func (c *Client) PublicID(folder, name string) string {
	folder = strings.Trim(folder, "/")
	name = strings.Trim(name, "/")
	if folder == "" {
		return name
	}
	return folder + "/" + name
}
