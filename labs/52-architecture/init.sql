CREATE TABLE IF NOT EXISTS quotes (
  id SERIAL PRIMARY KEY,
  author TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO quotes(author, text)
VALUES
  ('grace', 'Make it work, then make it right, then make it fast.'),
  ('linus', 'Talk is cheap. Show me the code.'),
  ('devops', 'If it hurts, do it more often.')
ON CONFLICT DO NOTHING;
