package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type LogLine struct {
	Timestamp  string `json:"ts"`
	Level      string `json:"level"`
	Message    string `json:"msg"`
	RequestID  string `json:"request_id,omitempty"`
	Method     string `json:"method,omitempty"`
	Path       string `json:"path,omitempty"`
	Status     int    `json:"status,omitempty"`
	LatencyMS  int64  `json:"latency_ms,omitempty"`
	RemoteAddr string `json:"remote_addr,omitempty"`
	Extra      any    `json:"extra,omitempty"`
}

func writeJSONLog(l LogLine) {
	b, _ := json.Marshal(l)
	fmt.Println(string(b))
}

var (
	// http_requests_total{method,route,status}
	reqsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "route", "status"},
	)

	// http_request_duration_seconds_bucket{method,route}
	reqDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "route"},
	)

	// app_events_total{type}
	appEvents = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "app_events_total",
			Help: "Application events (crash, forced_error, forced_slow, ok)",
		},
		[]string{"type"},
	)
)

func main() {
	rand.Seed(time.Now().UnixNano())

	prometheus.MustRegister(reqsTotal, reqDuration, appEvents)

	port := getenv("PORT", "3000")
	addr := ":" + port

	mux := http.NewServeMux()

	// Metrics
	mux.Handle("/metrics", promhttp.Handler())

	// Routes
	mux.HandleFunc("/", withObs("root", handleRoot))
	mux.HandleFunc("/slow", withObs("slow", handleSlow))
	mux.HandleFunc("/error", withObs("error", handleError))
	mux.HandleFunc("/crash", withObs("crash", handleCrash))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(200) })
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(200) })

	writeJSONLog(LogLine{
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		Level:     "info",
		Message:   "starting server",
		Extra: map[string]any{
			"addr": addr,
		},
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Fatal(srv.ListenAndServe())
}

func withObs(route string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// request_id: header -> fallback uuid
		reqID := r.Header.Get("X-Request-Id")
		if reqID == "" {
			reqID = uuid.NewString()
		}
		w.Header().Set("X-Request-Id", reqID)

		// capture status
		rw := &respWriter{ResponseWriter: w, status: 200}

		next(rw, r)

		lat := time.Since(start)
		status := rw.status

		reqsTotal.WithLabelValues(r.Method, route, strconv.Itoa(status)).Inc()
		reqDuration.WithLabelValues(r.Method, route).Observe(lat.Seconds())

		writeJSONLog(LogLine{
			Timestamp:  time.Now().UTC().Format(time.RFC3339Nano),
			Level:      "info",
			Message:    "request",
			RequestID:  reqID,
			Method:     r.Method,
			Path:       r.URL.Path,
			Status:     status,
			LatencyMS:  lat.Milliseconds(),
			RemoteAddr: r.RemoteAddr,
		})
	}
}

type respWriter struct {
	http.ResponseWriter
	status int
}

func (rw *respWriter) WriteHeader(code int) {
	rw.status = code
	rw.ResponseWriter.WriteHeader(code)
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	appEvents.WithLabelValues("ok").Inc()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"service": "metrics-log-api",
		"status":  "ok",
		"time":    time.Now().UTC().Format(time.RFC3339Nano),
	})
}

func handleSlow(w http.ResponseWriter, r *http.Request) {
	ms := atoiDefault(r.URL.Query().Get("ms"), 800)
	jitter := atoiDefault(r.URL.Query().Get("jitter"), 200)
	if jitter > 0 {
		ms += rand.Intn(jitter)
	}
	time.Sleep(time.Duration(ms) * time.Millisecond)

	appEvents.WithLabelValues("forced_slow").Inc()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"slow_ms": ms,
	})
}

func handleError(w http.ResponseWriter, r *http.Request) {
	code := atoiDefault(r.URL.Query().Get("code"), 500)
	if code < 400 || code > 599 {
		code = 500
	}
	appEvents.WithLabelValues("forced_error").Inc()
	http.Error(w, fmt.Sprintf("forced error %d", code), code)
}

func handleCrash(w http.ResponseWriter, r *http.Request) {
	appEvents.WithLabelValues("crash").Inc()
	writeJSONLog(LogLine{
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		Level:     "error",
		Message:   "forced crash requested",
		Extra: map[string]any{
			"path": r.URL.Path,
		},
	})
	// flush response then exit
	w.WriteHeader(200)
	_, _ = w.Write([]byte("crashing now\n"))
	_ = os.Stdout.Sync()
	os.Exit(1)
}

func atoiDefault(s string, def int) int {
	if s == "" {
		return def
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return def
	}
	return v
}

func getenv(k, def string) string {
	v := os.Getenv(k)
	if v == "" {
		return def
	}
	return v
}
