import { useState, useEffect } from 'react';
import { Plus, Trash2, Check } from 'lucide-react';

interface Task {
  id: string;
  title: string;
  description: string;
  completed: boolean;
  created_at: string;
}

interface HealthStatus {
  status: string;
  timestamp: string;
  database: string;
}

function App() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [health, setHealth] = useState<HealthStatus | null>(null);
  const [newTask, setNewTask] = useState({ title: '', description: '' });
  const [error, setError] = useState('');

  useEffect(() => {
    fetchHealth();
    fetchTasks();
  }, []);

  const fetchHealth = async () => {
    try {
      const response = await fetch('/api/health');
      const data = await response.json();
      setHealth(data);
    } catch (err) {
      console.error('Health check failed:', err);
    }
  };

  const fetchTasks = async () => {
    try {
      setLoading(true);
      const response = await fetch('/api/tasks');
      const data = await response.json();
      setTasks(data.tasks || []);
      setError('');
    } catch (err) {
      setError('Failed to fetch tasks');
      console.error('Error:', err);
    } finally {
      setLoading(false);
    }
  };

  const addTask = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newTask.title.trim()) return;

    try {
      const response = await fetch('/api/tasks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(newTask),
      });

      if (!response.ok) throw new Error('Failed to create task');

      const data = await response.json();
      setTasks([data.task, ...tasks]);
      setNewTask({ title: '', description: '' });
      setError('');
    } catch (err) {
      setError('Failed to create task');
      console.error('Error:', err);
    }
  };

  const toggleTask = async (id: string, completed: boolean) => {
    try {
      const response = await fetch(`/api/tasks/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ completed: !completed }),
      });

      if (!response.ok) throw new Error('Failed to update task');

      const data = await response.json();
      setTasks(tasks.map(task => task.id === id ? data.task : task));
    } catch (err) {
      setError('Failed to update task');
      console.error('Error:', err);
    }
  };

  const deleteTask = async (id: string) => {
    try {
      const response = await fetch(`/api/tasks/${id}`, {
        method: 'DELETE',
      });

      if (!response.ok) throw new Error('Failed to delete task');

      setTasks(tasks.filter(task => task.id !== id));
    } catch (err) {
      setError('Failed to delete task');
      console.error('Error:', err);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-blue-100">
      <div className="container mx-auto px-4 py-8 max-w-4xl">
        <div className="bg-white rounded-lg shadow-lg p-6 mb-6">
          <h1 className="text-3xl font-bold text-gray-800 mb-2">
            Kubernetes Task Manager
          </h1>
          <p className="text-gray-600 mb-4">
            Application web deployee sur Kubernetes avec base de donnees
          </p>

          {health && (
            <div className="flex items-center gap-4 text-sm">
              <span className="flex items-center gap-2">
                <span className={`w-2 h-2 rounded-full ${health.status === 'healthy' ? 'bg-green-500' : 'bg-red-500'}`}></span>
                Status: {health.status}
              </span>
              <span>Database: {health.database}</span>
            </div>
          )}
        </div>

        <div className="bg-white rounded-lg shadow-lg p-6 mb-6">
          <h2 className="text-xl font-semibold text-gray-800 mb-4">Add New Task</h2>
          <form onSubmit={addTask} className="space-y-4">
            <div>
              <input
                type="text"
                placeholder="Task title"
                value={newTask.title}
                onChange={(e) => setNewTask({ ...newTask, title: e.target.value })}
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>
            <div>
              <textarea
                placeholder="Task description (optional)"
                value={newTask.description}
                onChange={(e) => setNewTask({ ...newTask, description: e.target.value })}
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                rows={3}
              />
            </div>
            <button
              type="submit"
              className="w-full bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 transition-colors flex items-center justify-center gap-2"
            >
              <Plus size={20} />
              Add Task
            </button>
          </form>
        </div>

        {error && (
          <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded-lg mb-6">
            {error}
          </div>
        )}

        <div className="bg-white rounded-lg shadow-lg p-6">
          <h2 className="text-xl font-semibold text-gray-800 mb-4">Tasks</h2>

          {loading ? (
            <div className="text-center py-8 text-gray-500">Loading tasks...</div>
          ) : tasks.length === 0 ? (
            <div className="text-center py-8 text-gray-500">
              No tasks yet. Create your first task above!
            </div>
          ) : (
            <div className="space-y-3">
              {tasks.map((task) => (
                <div
                  key={task.id}
                  className="flex items-start gap-3 p-4 border border-gray-200 rounded-lg hover:shadow-md transition-shadow"
                >
                  <button
                    onClick={() => toggleTask(task.id, task.completed)}
                    className={`flex-shrink-0 w-6 h-6 rounded border-2 flex items-center justify-center transition-colors ${
                      task.completed
                        ? 'bg-green-500 border-green-500'
                        : 'border-gray-300 hover:border-green-500'
                    }`}
                  >
                    {task.completed && <Check size={16} className="text-white" />}
                  </button>

                  <div className="flex-1">
                    <h3 className={`font-medium ${task.completed ? 'line-through text-gray-500' : 'text-gray-800'}`}>
                      {task.title}
                    </h3>
                    {task.description && (
                      <p className="text-sm text-gray-600 mt-1">{task.description}</p>
                    )}
                  </div>

                  <button
                    onClick={() => deleteTask(task.id)}
                    className="flex-shrink-0 text-red-500 hover:text-red-700 transition-colors"
                  >
                    <Trash2 size={20} />
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default App;
