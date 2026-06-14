// nahui-app is the sample service we push through the pipeline. Kept small on
// purpose: the interesting part is the build/sign/verify stuff around it, not
// the app.
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/brawndon-manu/nahui/internal/server"
)

func main() {
	addr := os.Getenv("NAHUI_ADDR")
	if addr == "" {
		addr = ":8080"
	}

	srv := &http.Server{
		Addr:              addr,
		Handler:           server.New(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	// Wait for SIGINT/SIGTERM, then shut down cleanly so we don't drop
	// requests that are mid-flight.
	idleClosed := make(chan struct{})
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
		<-sig

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			log.Printf("graceful shutdown failed: %v", err)
		}
		close(idleClosed)
	}()

	log.Printf("nahui-app listening on %s (version %s)", addr, server.Version)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}

	<-idleClosed
	log.Print("nahui-app stopped")
}
