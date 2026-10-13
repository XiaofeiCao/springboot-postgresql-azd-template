package com.example.notes;

import java.time.Instant;
import java.util.UUID;

public record Note(UUID id, String title, String content, Instant createdAt) {
}
