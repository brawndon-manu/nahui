// HTTP handlers for nahui-app.
package server

import (
	"encoding/json"
	"net/http"
)

// Version gets set at build time with -ldflags "-X .../server.Version=<value>".
// Defaults to "dev" for local runs. We expose it on /version so we can check
// that a running container matches the commit/tag we signed.
var Version = "dev"

// New wires up the routes. Just enough to tell the app's alive and check the
// build version.
func New() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/healthz", handleHealth)
	mux.HandleFunc("/version", handleVersion)
	return mux
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte("Nahui — signed, attested, and verified, or it doesn't run.\n"))
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func handleVersion(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"version": Version})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
