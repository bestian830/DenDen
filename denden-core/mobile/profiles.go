// Package mobile provides GoMobile-compatible wrappers for the DenDen client.
// This file contains profile cache and query logic.
package mobile

import (
	"fmt"
)

// getProfileFromCache retrieves profile from cache (thread-safe)
func (d *DenDenClient) getProfileFromCache(pubkey string) Profile {
	d.cacheMutex.RLock()
	defer d.cacheMutex.RUnlock()

	if profile, exists := d.profileCache[pubkey]; exists {
		return profile
	}

	// Return empty profile if not cached
	return Profile{}
}

// GetProfile returns a profile as JSON string
// This allows Flutter to query profiles manually
func (d *DenDenClient) GetProfile(pubkey string) string {
	profile := d.getProfileFromCache(pubkey)

	if profile.Name == "" && profile.Picture == "" {
		// Profile not in cache
		return fmt.Sprintf(`{"pubkey":"%s","cached":false}`, pubkey)
	}

	// Return all 5 profile fields including banner and website
	return fmt.Sprintf(
		`{"pubkey":"%s","cached":true,"name":"%s","picture":"%s","about":"%s","banner":"%s","website":"%s"}`,
		pubkey,
		escapeJSON(profile.Name),
		escapeJSON(profile.Picture),
		escapeJSON(profile.About),
		escapeJSON(profile.Banner),
		escapeJSON(profile.Website),
	)
}
