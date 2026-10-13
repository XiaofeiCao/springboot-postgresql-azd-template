package com.example.notes;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record CreateNote(
        @NotBlank @Size(max = 200) String title,
        @NotBlank @Size(max = 10000) String content) {
}
