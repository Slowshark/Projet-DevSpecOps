const express = require('express');
const { createClient } = require('@supabase/supabase-js');
const { Pool } = require('pg');
const path = require('path');
const fs = require('fs');

const app = express();
const port = process.env.PORT || 3000;

// JSON file fallback when database is not configured
const dataFile = path.join(__dirname, 'data.json');

function readData() {
  try {
    const raw = fs.readFileSync(dataFile, 'utf8');
    return JSON.parse(raw);
  } catch (e) {
    return { tasks: [] };
  }
}

function writeData(data) {
  try {
    fs.writeFileSync(dataFile, JSON.stringify(data, null, 2));
  } catch (e) {
    console.error('Failed to write data file:', e.message);
  }
}

// Database configuration
let db = null;
let dbType = 'none'; // none, postgres, supabase, json

// Try PostgreSQL first (Kubernetes environment)
if (process.env.POSTGRES_HOST && process.env.POSTGRES_PORT && process.env.POSTGRES_DB) {
  try {
    const pgConfig = {
      host: process.env.POSTGRES_HOST,
      port: parseInt(process.env.POSTGRES_PORT, 10),
      database: process.env.POSTGRES_DB,
      user: process.env.POSTGRES_USER || 'admin',
      password: process.env.POSTGRES_PASSWORD || 'password',
      max: 5,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    };
    
    db = new Pool(pgConfig);
    
    // Test connection
    db.query('SELECT NOW()', (err, res) => {
      if (err) {
        console.error('PostgreSQL connection failed:', err.message);
        console.log('Falling back to JSON storage');
        db = null;
      } else {
        console.log('Connected to PostgreSQL');
        dbType = 'postgres';
      }
    });
  } catch (e) {
    console.error('Failed to initialize PostgreSQL client:', e.message);
    db = null;
  }
}

// Try Supabase (optional)
const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseKey = process.env.SUPABASE_ANON_KEY || '';

let supabase = null;
if (!db && supabaseUrl && supabaseKey && 
    !supabaseUrl.includes('example') && !supabaseKey.includes('example') && 
    !supabaseUrl.includes('your-')) {
  try {
    supabase = createClient(supabaseUrl, supabaseKey);
    console.log('Supabase client initialized');
    dbType = 'supabase';
  } catch (e) {
    console.error('Failed to initialize Supabase client:', e.message);
    supabase = null;
  }
}

// If no database, use JSON fallback
if (!db && !supabase) {
  console.log('No database configured, using JSON file fallback');
  dbType = 'json';
}

// Serve static files
const distPath = path.resolve(__dirname, '../dist');
console.log('Serving static files from:', distPath);
app.use(express.static(distPath));

app.use(express.json());

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    database: dbType
  });
});

// GET all tasks
app.get('/api/tasks', async (req, res) => {
  try {
    if (db) {
      try {
        const result = await db.query('SELECT * FROM tasks ORDER BY created_at DESC');
        return res.json({ tasks: result.rows });
      } catch (e) {
        console.error('PostgreSQL query failed, falling back to JSON:', e.message);
      }
    }
    
    if (supabase) {
      try {
        const { data, error } = await supabase
          .from('tasks')
          .select('*')
          .order('created_at', { ascending: false });
        if (error) throw error;
        return res.json({ tasks: data || [] });
      } catch (e) {
        console.error('Supabase query failed, falling back to JSON:', e.message);
      }
    }
    
    // JSON fallback
    const store = readData();
    store.tasks.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    return res.json({ tasks: store.tasks });
  } catch (error) {
    console.error('Error fetching tasks:', error);
    res.status(500).json({ error: error.message });
  }
});

// POST create task
app.post('/api/tasks', async (req, res) => {
  try {
    const { title, description } = req.body;
    if (!title) return res.status(400).json({ error: 'Title is required' });

    if (db) {
      try {
        const result = await db.query(
          'INSERT INTO tasks (title, description, completed) VALUES ($1, $2, $3) RETURNING *',
          [title, description || null, false]
        );
        return res.status(201).json({ task: result.rows[0] });
      } catch (e) {
        console.error('PostgreSQL insert failed, falling back to JSON:', e.message);
      }
    }
    
    if (supabase) {
      try {
        const { data, error } = await supabase
          .from('tasks')
          .insert([{ title, description, completed: false }])
          .select()
          .single();
        if (error) throw error;
        return res.status(201).json({ task: data });
      } catch (e) {
        console.error('Supabase insert failed, falling back to JSON:', e.message);
      }
    }
    
    // JSON fallback
    const store = readData();
    const nextId = store.tasks.reduce((max, t) => Math.max(max, t.id || 0), 0) + 1;
    const task = {
      id: nextId,
      title,
      description: description || null,
      completed: false,
      created_at: new Date().toISOString()
    };
    store.tasks.push(task);
    writeData(store);
    return res.status(201).json({ task });
  } catch (error) {
    console.error('Error creating task:', error);
    res.status(500).json({ error: error.message });
  }
});

// PUT update task
app.put('/api/tasks/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { completed } = req.body;

    if (db) {
      try {
        const result = await db.query(
          'UPDATE tasks SET completed = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
          [!!completed, id]
        );
        if (result.rows.length === 0) {
          return res.status(404).json({ error: 'Task not found' });
        }
        return res.json({ task: result.rows[0] });
      } catch (e) {
        console.error('PostgreSQL update failed, falling back to JSON:', e.message);
      }
    }
    
    if (supabase) {
      try {
        const { data, error } = await supabase
          .from('tasks')
          .update({ completed })
          .eq('id', id)
          .select()
          .single();
        if (error) throw error;
        return res.json({ task: data });
      } catch (e) {
        console.error('Supabase update failed, falling back to JSON:', e.message);
      }
    }
    
    // JSON fallback
    const store = readData();
    const t = store.tasks.find(x => String(x.id) === String(id));
    if (!t) return res.status(404).json({ error: 'Task not found' });
    t.completed = !!completed;
    writeData(store);
    return res.json({ task: t });
  } catch (error) {
    console.error('Error updating task:', error);
    res.status(500).json({ error: error.message });
  }
});

// DELETE task
app.delete('/api/tasks/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (db) {
      try {
        const result = await db.query('DELETE FROM tasks WHERE id = $1 RETURNING id', [id]);
        if (result.rows.length === 0) {
          return res.status(404).json({ error: 'Task not found' });
        }
        return res.json({ message: 'Task deleted successfully' });
      } catch (e) {
        console.error('PostgreSQL delete failed, falling back to JSON:', e.message);
      }
    }
    
    if (supabase) {
      try {
        const { error } = await supabase
          .from('tasks')
          .delete()
          .eq('id', id);
        if (error) throw error;
        return res.json({ message: 'Task deleted successfully' });
      } catch (e) {
        console.error('Supabase delete failed, falling back to JSON:', e.message);
      }
    }
    
    // JSON fallback
    const store = readData();
    const before = store.tasks.length;
    store.tasks = store.tasks.filter(x => String(x.id) !== String(id));
    writeData(store);
    if (store.tasks.length === before) return res.status(404).json({ error: 'Task not found' });
    return res.json({ message: 'Task deleted successfully' });
  } catch (error) {
    console.error('Error deleting task:', error);
    res.status(500).json({ error: error.message });
  }
});

// Serve index.html for all unmatched routes (SPA fallback)
app.get('*', (req, res) => {
  res.sendFile(path.resolve(__dirname, '../dist/index.html'));
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Server running on port ${port}`);
  console.log(`Database type: ${dbType}`);
});
