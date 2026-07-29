// Command webserve serves a generated web bundle on loopback with the MIME
// types and cache policy needed for local WebAssembly acceptance.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"practice_love2d/33_ebitengine_spike/internal/webdist"
	"syscall"
	"time"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "webserve:", err)
		os.Exit(1)
	}
}

func run(arguments []string) error {
	flags := flag.NewFlagSet("webserve", flag.ContinueOnError)
	rootValue := flags.String("root", "dist/web", "generated web bundle")
	address := flags.String(
		"listen",
		"127.0.0.1:8080",
		"loopback HTTP address",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New(
			"usage: webserve [-root dist/web] [-listen 127.0.0.1:8080]",
		)
	}
	if err := webdist.ValidateListenAddress(*address); err != nil {
		return err
	}
	root, err := webdist.Verify(*rootValue)
	if err != nil {
		return err
	}
	listener, err := net.Listen("tcp", *address)
	if err != nil {
		return err
	}
	defer listener.Close()

	server := &http.Server{
		Handler:           webdist.Handler(root),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      2 * time.Minute,
		IdleTimeout:       30 * time.Second,
	}
	serverErrors := make(chan error, 1)
	go func() {
		serverErrors <- server.Serve(listener)
	}()
	fmt.Printf("Recreate web: http://%s/\n", listener.Addr())

	ctx, stop := signal.NotifyContext(
		context.Background(),
		os.Interrupt,
		syscall.SIGTERM,
	)
	defer stop()
	select {
	case <-ctx.Done():
	case err := <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	}
	shutdown, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	return server.Shutdown(shutdown)
}
