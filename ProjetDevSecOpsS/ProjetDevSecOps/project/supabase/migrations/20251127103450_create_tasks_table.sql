/*
  # Create Tasks Table

  1. New Tables
    - `tasks`
      - `id` (uuid, primary key) - Unique identifier for each task
      - `title` (text, required) - Title of the task
      - `description` (text, optional) - Detailed description of the task
      - `completed` (boolean) - Whether the task is completed or not
      - `created_at` (timestamptz) - When the task was created
      - `updated_at` (timestamptz) - When the task was last updated

  2. Security
    - Enable RLS on `tasks` table
    - Add policy for public access to read tasks
    - Add policy for public access to insert tasks
    - Add policy for public access to update tasks
    - Add policy for public access to delete tasks

  3. Indexes
    - Index on created_at for efficient sorting
    - Index on completed for filtering

  Note: In a production environment, you would restrict access to authenticated users only.
  For this demo project, we allow public access.
*/

CREATE TABLE IF NOT EXISTS tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    description text DEFAULT '',
    completed boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view tasks"
  ON tasks FOR SELECT
  USING (true);

CREATE POLICY "Anyone can insert tasks"
  ON tasks FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Anyone can update tasks"
  ON tasks FOR UPDATE
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Anyone can delete tasks"
  ON tasks FOR DELETE
  USING (true);

CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_completed ON tasks(completed);

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_tasks_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

INSERT INTO tasks (title, description, completed) VALUES
    ('Deployer PostgreSQL sur Kubernetes', 'Creer les fichiers YAML pour le deployment de PostgreSQL', true),
    ('Deployer l''application web', 'Creer les fichiers YAML pour le deployment de l''application Node.js', true),
    ('Configurer les Services', 'Creer les services ClusterIP et NodePort', true),
    ('Tester l''application', 'Verifier que tout fonctionne correctement', false);