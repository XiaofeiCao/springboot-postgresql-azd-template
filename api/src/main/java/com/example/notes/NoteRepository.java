package com.example.notes;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class NoteRepository {
    private final JdbcClient jdbc;

    public NoteRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public Note create(CreateNote request) {
        return jdbc.sql("""
                INSERT INTO notes (id, title, content) VALUES (:id, :title, :content)
                RETURNING id, title, content, created_at
                """)
                .param("id", UUID.randomUUID())
                .param("title", request.title())
                .param("content", request.content())
                .query(NoteRepository::map)
                .single();
    }

    public Optional<Note> find(UUID id) {
        return jdbc.sql("SELECT id, title, content, created_at FROM notes WHERE id = :id")
                .param("id", id).query(NoteRepository::map).optional();
    }

    public List<Note> list() {
        return jdbc.sql("SELECT id, title, content, created_at FROM notes ORDER BY created_at DESC, id")
                .query(NoteRepository::map).list();
    }

    private static Note map(ResultSet row, int rowNumber) throws SQLException {
        return new Note(row.getObject("id", UUID.class), row.getString("title"),
                row.getString("content"), row.getTimestamp("created_at").toInstant());
    }
}
