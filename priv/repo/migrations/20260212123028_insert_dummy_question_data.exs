defmodule VyaasaCampus.Repo.Migrations.InsertDummyQuestionData do
  use Ecto.Migration

  def up do
    # Insert Qualifications
    execute """
    INSERT INTO qualifications (id, name, graduation_level, field_of_study, inserted_at, updated_at)
    VALUES
      (1, 'B.Tech', 'Undergraduate', 'Engineering', NOW(), NOW()),
      (2, 'BCA', 'Undergraduate', 'Computer Applications', NOW(), NOW()),
      (3, 'MCA', 'Postgraduate', 'Computer Applications', NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # Insert Branches
    execute """
    INSERT INTO branches (id, name, specialization, code, qualification_id, inserted_at, updated_at)
    VALUES
      (1, 'Computer Science', 'Software Engineering', 'CSE', 1, NOW(), NOW()),
      (2, 'Information Technology', 'IT Systems', 'IT', 1, NOW(), NOW()),
      (3, 'Computer Applications', 'Software Development', 'CA', 2, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # Insert Curricula
    execute """
    INSERT INTO curricula (id, name, code, branch_id, inserted_at, updated_at)
    VALUES
      (1, '2024 Computer Science Curriculum', 'CSE2024', 1, NOW(), NOW()),
      (2, '2024 IT Curriculum', 'IT2024', 2, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # Insert Subjects
    execute """
    INSERT INTO subjects (id, name, code, credits, inserted_at, updated_at)
    VALUES
      (1, 'Data Structures', 'CS201', 4, NOW(), NOW()),
      (2, 'Algorithms', 'CS202', 4, NOW(), NOW()),
      (3, 'Database Management', 'CS301', 3, NOW(), NOW()),
      (4, 'Web Development', 'CS302', 3, NOW(), NOW()),
      (5, 'Operating Systems', 'CS303', 4, NOW(), NOW()),
      (6, 'Computer Networks', 'CS304', 3, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # Link Curricula to Subjects
    execute """
    INSERT INTO curricula_subjects (curricula_id, subject_id, branch_id, inserted_at, updated_at)
    VALUES
      (1, 1, 1, NOW(), NOW()),
      (1, 2, 1, NOW(), NOW()),
      (1, 3, 1, NOW(), NOW()),
      (1, 4, 1, NOW(), NOW()),
      (1, 5, 1, NOW(), NOW()),
      (1, 6, 1, NOW(), NOW())
    ON CONFLICT (curricula_id, subject_id, branch_id) DO NOTHING;
    """

    # Insert Topics
    execute """
    INSERT INTO topics (id, name, type, weightage, subject_id, inserted_at, updated_at)
    VALUES
      -- Data Structures Topics
      (1, 'Arrays and Strings', 'core', 1.0, 1, NOW(), NOW()),
      (2, 'Linked Lists', 'core', 1.2, 1, NOW(), NOW()),
      (3, 'Stacks and Queues', 'core', 1.0, 1, NOW(), NOW()),
      (4, 'Trees and Graphs', 'advanced', 1.5, 1, NOW(), NOW()),
      -- Algorithms Topics
      (5, 'Sorting Algorithms', 'core', 1.2, 2, NOW(), NOW()),
      (6, 'Searching Algorithms', 'core', 1.0, 2, NOW(), NOW()),
      (7, 'Dynamic Programming', 'advanced', 1.8, 2, NOW(), NOW()),
      -- Database Topics
      (8, 'SQL Basics', 'core', 1.0, 3, NOW(), NOW()),
      (9, 'Normalization', 'core', 1.2, 3, NOW(), NOW()),
      (10, 'Transactions', 'advanced', 1.3, 3, NOW(), NOW()),
      -- Web Development Topics
      (11, 'HTML & CSS', 'core', 0.8, 4, NOW(), NOW()),
      (12, 'JavaScript', 'core', 1.2, 4, NOW(), NOW()),
      (13, 'REST APIs', 'advanced', 1.5, 4, NOW(), NOW()),
      -- Operating Systems Topics
      (14, 'Process Management', 'core', 1.3, 5, NOW(), NOW()),
      (15, 'Memory Management', 'advanced', 1.5, 5, NOW(), NOW()),
      -- Networks Topics
      (16, 'OSI Model', 'core', 1.0, 6, NOW(), NOW()),
      (17, 'TCP/IP', 'core', 1.2, 6, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # Insert Questions - Data Structures (Beginner)
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (1, 'What is the time complexity of accessing an element in an array by index?',
       'a', 'beginner',
       '{"a": "O(1)", "b": "O(n)", "c": "O(log n)", "d": "O(n^2)"}',
       'multiple_choice', 1.0, 1, NOW(), NOW()),

      (2, 'Which data structure uses LIFO (Last In First Out) principle?',
       'b', 'beginner',
       '{"a": "Queue", "b": "Stack", "c": "Array", "d": "Linked List"}',
       'multiple_choice', 1.0, 3, NOW(), NOW()),

      (3, 'In a linked list, what does each node contain?',
       'c', 'beginner',
       '{"a": "Only data", "b": "Only pointer", "c": "Data and pointer", "d": "Index"}',
       'multiple_choice', 1.0, 2, NOW(), NOW()),

      (4, 'What is the main advantage of using a queue?',
       'a', 'beginner',
       '{"a": "FIFO ordering", "b": "Random access", "c": "Fast sorting", "d": "Memory efficiency"}',
       'multiple_choice', 1.0, 3, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # Insert Questions - Algorithms (Intermediate)
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (5, 'What is the time complexity of binary search in a sorted array?',
       'b', 'intermediate',
       '{"a": "O(n)", "b": "O(log n)", "c": "O(n log n)", "d": "O(1)"}',
       'multiple_choice', 1.0, 6, NOW(), NOW()),

      (6, 'Which sorting algorithm has the best average-case time complexity?',
       'c', 'intermediate',
       '{"a": "Bubble Sort", "b": "Insertion Sort", "c": "Merge Sort", "d": "Selection Sort"}',
       'multiple_choice', 1.0, 5, NOW(), NOW()),

      (7, 'What is Big O notation used for?',
       'b', 'intermediate',
       '{"a": "Measuring memory only", "b": "Analyzing algorithm efficiency", "c": "Debugging code", "d": "Writing documentation"}',
       'multiple_choice', 1.0, 6, NOW(), NOW()),

      (8, 'Which algorithm technique is used in Quick Sort?',
       'a', 'intermediate',
       '{"a": "Divide and Conquer", "b": "Dynamic Programming", "c": "Greedy", "d": "Backtracking"}',
       'multiple_choice', 1.0, 5, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # Insert Questions - Database (Beginner & Intermediate)
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (9, 'What does SQL stand for?',
       'a', 'beginner',
       '{"a": "Structured Query Language", "b": "Simple Query Language", "c": "System Query Language", "d": "Standard Query Language"}',
       'multiple_choice', 1.0, 8, NOW(), NOW()),

      (10, 'Which of the following is NOT a relational database?',
       'c', 'beginner',
       '{"a": "MySQL", "b": "PostgreSQL", "c": "MongoDB", "d": "Oracle"}',
       'multiple_choice', 1.0, 8, NOW(), NOW()),

      (11, 'What is the purpose of normalization in databases?',
       'b', 'intermediate',
       '{"a": "Increase redundancy", "b": "Reduce redundancy", "c": "Slow down queries", "d": "Increase storage"}',
       'multiple_choice', 1.0, 9, NOW(), NOW()),

      (12, 'Which SQL command is used to retrieve data from a database?',
       'd', 'beginner',
       '{"a": "INSERT", "b": "UPDATE", "c": "DELETE", "d": "SELECT"}',
       'multiple_choice', 1.0, 8, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # Insert Questions - Web Development (Beginner & Intermediate)
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (13, 'What does HTML stand for?',
       'a', 'beginner',
       '{"a": "HyperText Markup Language", "b": "High Tech Modern Language", "c": "Home Tool Markup Language", "d": "Hyperlinks and Text Markup Language"}',
       'multiple_choice', 1.0, 11, NOW(), NOW()),

      (14, 'Which HTTP method is used to update a resource?',
       'c', 'intermediate',
       '{"a": "GET", "b": "POST", "c": "PUT", "d": "DELETE"}',
       'multiple_choice', 1.0, 13, NOW(), NOW()),

      (15, 'What is the output of 2 + ''2'' in JavaScript?',
       'b', 'intermediate',
       '{"a": "4", "b": "22", "c": "NaN", "d": "Error"}',
       'multiple_choice', 1.0, 12, NOW(), NOW()),

      (16, 'Which CSS property is used to change text color?',
       'a', 'beginner',
       '{"a": "color", "b": "text-color", "c": "font-color", "d": "text-style"}',
       'multiple_choice', 1.0, 11, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # Insert Questions - Advanced
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (17, 'What is the space complexity of merge sort?',
       'b', 'advanced',
       '{"a": "O(1)", "b": "O(n)", "c": "O(log n)", "d": "O(n^2)"}',
       'multiple_choice', 1.0, 5, NOW(), NOW()),

      (18, 'Which tree traversal uses a stack data structure?',
       'd', 'advanced',
       '{"a": "Level order", "b": "Breadth-first", "c": "Both A and B", "d": "Depth-first"}',
       'multiple_choice', 1.0, 4, NOW(), NOW()),

      (19, 'What is the main principle of dynamic programming?',
       'c', 'advanced',
       '{"a": "Divide and conquer", "b": "Greedy choice", "c": "Optimal substructure and overlapping subproblems", "d": "Backtracking"}',
       'multiple_choice', 1.0, 7, NOW(), NOW()),

      (20, 'In database ACID properties, what does I stand for?',
       'b', 'advanced',
       '{"a": "Integrity", "b": "Isolation", "c": "Identity", "d": "Independence"}',
       'multiple_choice', 1.0, 10, NOW(), NOW()),

      (21, 'What is the purpose of the virtual DOM in React?',
       'a', 'advanced',
       '{"a": "Optimize rendering performance", "b": "Store application state", "c": "Handle routing", "d": "Manage API calls"}',
       'multiple_choice', 1.0, 12, NOW(), NOW()),

      (22, 'Which page replacement algorithm suffers from Belady''s anomaly?',
       'd', 'advanced',
       '{"a": "LRU", "b": "Optimal", "c": "LFU", "d": "FIFO"}',
       'multiple_choice', 1.0, 15, NOW(), NOW()),

      (23, 'What is the main difference between TCP and UDP?',
       'c', 'intermediate',
       '{"a": "Speed only", "b": "Port numbers", "c": "Reliability and connection", "d": "Packet size"}',
       'multiple_choice', 1.0, 17, NOW(), NOW()),

      (24, 'Which layer of OSI model handles routing?',
       'b', 'intermediate',
       '{"a": "Data Link", "b": "Network", "c": "Transport", "d": "Session"}',
       'multiple_choice', 1.0, 16, NOW(), NOW()),

      (25, 'What is a deadlock in operating systems?',
       'd', 'advanced',
       '{"a": "Process termination", "b": "Memory overflow", "c": "CPU overload", "d": "Circular wait for resources"}',
       'multiple_choice', 1.0, 14, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # Reset sequences to avoid conflicts
    execute "SELECT setval('qualifications_id_seq', (SELECT MAX(id) FROM qualifications));"
    execute "SELECT setval('branches_id_seq', (SELECT MAX(id) FROM branches));"
    execute "SELECT setval('curricula_id_seq', (SELECT MAX(id) FROM curricula));"
    execute "SELECT setval('subjects_id_seq', (SELECT MAX(id) FROM subjects));"
    execute "SELECT setval('topics_id_seq', (SELECT MAX(id) FROM topics));"
    execute "SELECT setval('qa_id_seq', (SELECT MAX(id) FROM qa));"
  end

  def down do
    execute "DELETE FROM qa WHERE id BETWEEN 1 AND 25;"
    execute "DELETE FROM topics WHERE id BETWEEN 1 AND 17;"
    execute "DELETE FROM curricula_subjects;"
    execute "DELETE FROM subjects WHERE id BETWEEN 1 AND 6;"
    execute "DELETE FROM curricula WHERE id IN (1, 2);"
    execute "DELETE FROM branches WHERE id IN (1, 2, 3);"
    execute "DELETE FROM qualifications WHERE id IN (1, 2, 3);"
  end
end
