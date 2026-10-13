package com.example.notes;

import java.net.URI;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/notes")
public class NoteController {
    private final NoteRepository repository;

    public NoteController(NoteRepository repository) {
        this.repository = repository;
    }

    @PostMapping
    public ResponseEntity<Note> create(@Valid @RequestBody CreateNote request) {
        Note note = repository.create(request);
        return ResponseEntity.created(URI.create("/notes/" + note.id())).body(note);
    }

    @GetMapping("/{id}")
    public Note get(@PathVariable UUID id) {
        return repository.find(id).orElseThrow(NoteNotFoundException::new);
    }

    @GetMapping
    public List<Note> list() {
        return repository.list();
    }
}
