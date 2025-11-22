package main

import (
	"html/template"
	"log"
	"net/http"
	"sync"
)

// Todo represents a single todo item
type Todo struct {
	Title string
}

// In-memory storage for todo items
type TodoListStore struct {
	mu       sync.Mutex
	todoList []Todo
}

var todoListStore = &TodoListStore{
	todoList: []Todo{},
}

// Template for rendering the todo list
var tmpl = template.Must(template.ParseFiles("./index.html"))

// getTodoHandler handles GET requests to retrieve the todo list
func getTodoHandler(w http.ResponseWriter, r *http.Request) {
	tmpl.Execute(w, todoListStore.todoList)
}

// postTodoHandler handles POST requests to add a new todo item
func postTodoHandler(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "Failed to parse form", http.StatusBadRequest)
		return
	}
	title := r.FormValue("title")
	if title != "" {
		todoListStore.mu.Lock()
		todoListStore.todoList = append(todoListStore.todoList, Todo{Title: title})
		todoListStore.mu.Unlock()
	}

	http.Redirect(w, r, "/todos", http.StatusSeeOther)
}

// responseRecorder is a custom ResponseWriter to capture the status code
type responseRecorder struct {
	http.ResponseWriter
	status int
}

func (r *responseRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// accessLogMiddleware logs each incoming HTTP request
func accessLogMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &responseRecorder{ResponseWriter: w, status: 200}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s %s %d", r.RemoteAddr, r.Method, r.URL, rec.status)
	})
}

func main() {
	mux := http.NewServeMux()

	mux.Handle("GET /todos", http.HandlerFunc(getTodoHandler))
	mux.Handle("POST /todos", http.HandlerFunc(postTodoHandler))
	mux.Handle("GET /healthz", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	http.ListenAndServe(":8080", accessLogMiddleware(mux))
}
