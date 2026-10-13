CREATE TABLE IF NOT EXISTS notes (
    id UUID PRIMARY KEY,
    title VARCHAR(200) NOT NULL CHECK (length(trim(title)) > 0),
    content TEXT NOT NULL CHECK (length(trim(content)) > 0 AND length(content) <= 10000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
