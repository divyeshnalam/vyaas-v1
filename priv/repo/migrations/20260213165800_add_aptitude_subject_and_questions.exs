defmodule VyaasaCampus.Repo.Migrations.AddAptitudeSubjectAndQuestions do
  use Ecto.Migration

  @moduledoc """
  Adds Aptitude as a global subject with topics and questions.
  Links it to all existing curricula/branches so every assessment
  includes aptitude questions as the first section.

  Topics:
  - Quantitative Aptitude (Number Systems, Percentages, Profit & Loss, Time & Work, etc.)
  - Verbal Ability (Reading Comprehension, Grammar, Vocabulary)
  - Logical Reasoning (Patterns, Syllogisms, Blood Relations, Coding-Decoding)
  """

  def up do
    # =========================================================================
    # 1. Create Aptitude Subject
    # =========================================================================
    execute """
    INSERT INTO subjects (id, name, code, credits, inserted_at, updated_at)
    VALUES (7, 'Aptitude', 'APT101', 0, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # =========================================================================
    # 2. Create Aptitude Topics
    # =========================================================================
    execute """
    INSERT INTO topics (id, name, type, weightage, subject_id, inserted_at, updated_at)
    VALUES
      (18, 'Quantitative Aptitude', 'core', 1.5, 7, NOW(), NOW()),
      (19, 'Verbal Ability', 'core', 1.2, 7, NOW(), NOW()),
      (20, 'Logical Reasoning', 'core', 1.5, 7, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # =========================================================================
    # 3. Link Aptitude to ALL existing curricula and branches
    # =========================================================================
    execute """
    INSERT INTO curricula_subjects (curricula_id, subject_id, branch_id, inserted_at, updated_at)
    SELECT c.id, 7, c.branch_id, NOW(), NOW()
    FROM curricula c
    WHERE NOT EXISTS (
      SELECT 1 FROM curricula_subjects cs
      WHERE cs.curricula_id = c.id AND cs.subject_id = 7 AND cs.branch_id = c.branch_id
    );
    """

    # =========================================================================
    # 4. Insert Quantitative Aptitude Questions (20 questions)
    # =========================================================================

    # -- Easy --
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (26, 'What is 15% of 200?',
       'b', 'easy',
       '{"a": "20", "b": "30", "c": "35", "d": "25"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (27, 'If a shirt costs Rs. 500 and is sold at Rs. 600, what is the profit percentage?',
       'c', 'easy',
       '{"a": "10%", "b": "15%", "c": "20%", "d": "25%"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (28, 'What is the average of 10, 20, 30, 40 and 50?',
       'b', 'easy',
       '{"a": "25", "b": "30", "c": "35", "d": "40"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (29, 'A train travels 120 km in 2 hours. What is its speed?',
       'a', 'easy',
       '{"a": "60 km/h", "b": "50 km/h", "c": "70 km/h", "d": "80 km/h"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (30, 'What is the simple interest on Rs. 1000 at 10% per annum for 2 years?',
       'b', 'easy',
       '{"a": "100", "b": "200", "c": "150", "d": "250"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (31, 'If 3x + 5 = 20, what is the value of x?',
       'a', 'easy',
       '{"a": "5", "b": "6", "c": "4", "d": "7"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (32, 'What is the LCM of 4 and 6?',
       'c', 'easy',
       '{"a": "6", "b": "8", "c": "12", "d": "24"}',
       'multiple_choice', 1.0, 18, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # -- Medium --
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (33, 'A can do a piece of work in 10 days and B can do it in 15 days. In how many days can they do it together?',
       'b', 'medium',
       '{"a": "5 days", "b": "6 days", "c": "7 days", "d": "8 days"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (34, 'The ratio of boys to girls in a class is 3:2. If there are 30 boys, how many girls are there?',
       'a', 'medium',
       '{"a": "20", "b": "25", "c": "15", "d": "18"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (35, 'A shopkeeper marks up the price by 25% and then gives a discount of 10%. What is the net profit percentage?',
       'b', 'medium',
       '{"a": "10%", "b": "12.5%", "c": "15%", "d": "13.5%"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (36, 'Two pipes can fill a tank in 12 hours and 18 hours respectively. How long will they take to fill the tank together?',
       'c', 'medium',
       '{"a": "6 hours", "b": "6.5 hours", "c": "7.2 hours", "d": "8 hours"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (37, 'If the compound interest on a sum for 2 years at 10% per annum is Rs. 210, what is the principal?',
       'b', 'medium',
       '{"a": "900", "b": "1000", "c": "1100", "d": "1200"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (38, 'A boat goes 12 km upstream in 3 hours and 16 km downstream in 2 hours. What is the speed of the stream?',
       'a', 'medium',
       '{"a": "2 km/h", "b": "3 km/h", "c": "4 km/h", "d": "1 km/h"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (39, 'In how many ways can 5 books be arranged on a shelf?',
       'd', 'medium',
       '{"a": "25", "b": "60", "c": "100", "d": "120"}',
       'multiple_choice', 1.0, 18, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # -- Hard --
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (40, 'A sum of money doubles itself in 8 years at simple interest. What is the rate of interest?',
       'b', 'hard',
       '{"a": "10%", "b": "12.5%", "c": "15%", "d": "8%"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (41, 'The product of two numbers is 120 and their HCF is 6. How many such pairs exist?',
       'c', 'hard',
       '{"a": "1", "b": "2", "c": "3", "d": "4"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (42, 'A mixture contains milk and water in the ratio 5:3. If 16 liters of the mixture is replaced with water, the ratio becomes 3:5. What was the original quantity?',
       'b', 'hard',
       '{"a": "36 liters", "b": "40 liters", "c": "48 liters", "d": "32 liters"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (43, 'A clock shows 3:15. What is the angle between the hour and minute hands?',
       'a', 'hard',
       '{"a": "7.5 degrees", "b": "0 degrees", "c": "15 degrees", "d": "22.5 degrees"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (44, 'Three unbiased coins are tossed. What is the probability of getting at least 2 heads?',
       'c', 'hard',
       '{"a": "1/4", "b": "3/8", "c": "1/2", "d": "5/8"}',
       'multiple_choice', 1.0, 18, NOW(), NOW()),

      (45, 'If log(x) + log(x+3) = 1, what is the value of x?',
       'b', 'hard',
       '{"a": "1", "b": "2", "c": "3", "d": "5"}',
       'multiple_choice', 1.0, 18, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # =========================================================================
    # 5. Insert Verbal Ability Questions (15 questions)
    # =========================================================================

    # -- Easy --
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (46, 'Choose the synonym of "Benevolent":',
       'a', 'easy',
       '{"a": "Kind", "b": "Cruel", "c": "Selfish", "d": "Angry"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (47, 'Choose the antonym of "Abundant":',
       'c', 'easy',
       '{"a": "Plentiful", "b": "Excess", "c": "Scarce", "d": "Rich"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (48, 'Identify the correctly spelled word:',
       'b', 'easy',
       '{"a": "Accomodate", "b": "Accommodate", "c": "Acomodate", "d": "Acommodate"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (49, 'Choose the correct preposition: "She is good ___ mathematics."',
       'a', 'easy',
       '{"a": "at", "b": "in", "c": "on", "d": "with"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (50, 'Which sentence is grammatically correct?',
       'c', 'easy',
       '{"a": "He go to school every day.", "b": "He going to school every day.", "c": "He goes to school every day.", "d": "He gone to school every day."}',
       'multiple_choice', 1.0, 19, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # -- Medium --
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (51, 'Choose the word that best completes the sentence: "The manager''s decision was ___; no one could change it."',
       'b', 'medium',
       '{"a": "flexible", "b": "irrevocable", "c": "temporary", "d": "uncertain"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (52, 'Identify the figure of speech in: "The world is a stage."',
       'a', 'medium',
       '{"a": "Metaphor", "b": "Simile", "c": "Hyperbole", "d": "Personification"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (53, 'Choose the correct form: "Neither the teacher nor the students ___ present."',
       'd', 'medium',
       '{"a": "is", "b": "has been", "c": "was", "d": "were"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (54, 'What is the meaning of the idiom "to burn the midnight oil"?',
       'b', 'medium',
       '{"a": "To waste resources", "b": "To study or work late into the night", "c": "To set fire", "d": "To be very angry"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (55, 'Choose the one-word substitute for "a person who speaks many languages":',
       'c', 'medium',
       '{"a": "Linguist", "b": "Bilingual", "c": "Polyglot", "d": "Translator"}',
       'multiple_choice', 1.0, 19, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # -- Hard --
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (56, 'Choose the correct sentence:',
       'a', 'hard',
       '{"a": "Had I known earlier, I would have helped.", "b": "Had I knew earlier, I would have helped.", "c": "If I had knew, I would helped.", "d": "Had I know earlier, I will have helped."}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (57, '"Ephemeral" most closely means:',
       'b', 'hard',
       '{"a": "Eternal", "b": "Short-lived", "c": "Beautiful", "d": "Mysterious"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (58, 'Identify the error: "Each of the boys have completed their assignment."',
       'a', 'hard',
       '{"a": "have should be has", "b": "their should be its", "c": "Each should be Every", "d": "No error"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (59, 'The phrase "a red herring" means:',
       'd', 'hard',
       '{"a": "A type of fish", "b": "A warning sign", "c": "An important clue", "d": "Something misleading or distracting"}',
       'multiple_choice', 1.0, 19, NOW(), NOW()),

      (60, 'Choose the word most opposite in meaning to "Pragmatic":',
       'c', 'hard',
       '{"a": "Practical", "b": "Realistic", "c": "Idealistic", "d": "Sensible"}',
       'multiple_choice', 1.0, 19, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # =========================================================================
    # 6. Insert Logical Reasoning Questions (15 questions)
    # =========================================================================

    # -- Easy --
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (61, 'Find the next number in the series: 2, 6, 12, 20, ?',
       'c', 'easy',
       '{"a": "25", "b": "28", "c": "30", "d": "32"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (62, 'If APPLE is coded as ELPPA, then MANGO is coded as:',
       'b', 'easy',
       '{"a": "OGMAN", "b": "OGNAM", "c": "NAMGO", "d": "GONMA"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (63, 'All roses are flowers. Some flowers are red. Which conclusion is correct?',
       'c', 'easy',
       '{"a": "All roses are red", "b": "No roses are red", "c": "Some roses may be red", "d": "All flowers are roses"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (64, 'Pointing to a man, a woman said "He is the son of my father''s only daughter." How is the man related to the woman?',
       'a', 'easy',
       '{"a": "Son", "b": "Brother", "c": "Nephew", "d": "Father"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (65, 'If Monday falls on 1st of a month, what day will the 15th be?',
       'b', 'easy',
       '{"a": "Sunday", "b": "Monday", "c": "Tuesday", "d": "Saturday"}',
       'multiple_choice', 1.0, 20, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # -- Medium --
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (66, 'Find the odd one out: 3, 5, 11, 14, 17, 21',
       'c', 'medium',
       '{"a": "__(3)", "b": "5", "c": "14", "d": "21"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (67, 'In a certain code language, COMPUTER is written as RFUVQNPC. How is LANGUAGE written?',
       'a', 'medium',
       '{"a": "FHBVHOBM", "b": "MBOHVBHF", "c": "BHFMVOBH", "d": "LANGUAHE"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (68, 'A is the father of B. B is the sister of C. D is the husband of C. How is A related to D?',
       'b', 'medium',
       '{"a": "Brother", "b": "Father-in-law", "c": "Uncle", "d": "Grandfather"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (69, 'Statements: All dogs are animals. All animals are living beings. Conclusion: All dogs are living beings.',
       'a', 'medium',
       '{"a": "The conclusion follows", "b": "The conclusion does not follow", "c": "The data is insufficient", "d": "None of these"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (70, 'If + means -, - means x, x means / and / means +, then what is the value of 12 + 6 - 3 x 2 / 8?',
       'c', 'medium',
       '{"a": "10", "b": "12", "c": "17", "d": "15"}',
       'multiple_choice', 1.0, 20, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # -- Hard --
    execute """
    INSERT INTO qa (id, question, answer, difficulty_level, options, type, weightage, topic_id, inserted_at, updated_at)
    VALUES
      (71, 'Find the missing number: 1, 4, 27, 256, ?',
       'd', 'hard',
       '{"a": "625", "b": "1024", "c": "2048", "d": "3125"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (72, 'Six people A, B, C, D, E, F sit in a circle. A is between E and F. B is between D and C. D is not next to E. Who is sitting opposite to A?',
       'b', 'hard',
       '{"a": "C", "b": "D", "c": "B", "d": "E"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (73, 'Statements: Some pens are pencils. No pencil is an eraser. Conclusions: I. Some pens are not erasers. II. Some pencils are pens.',
       'c', 'hard',
       '{"a": "Only I follows", "b": "Only II follows", "c": "Both I and II follow", "d": "Neither follows"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (74, 'A cube has all faces painted red. It is cut into 64 identical smaller cubes. How many smaller cubes have exactly two faces painted?',
       'b', 'hard',
       '{"a": "20", "b": "24", "c": "28", "d": "32"}',
       'multiple_choice', 1.0, 20, NOW(), NOW()),

      (75, 'In a family, there are 6 members: A, B, C, D, E, F. A and B are married couple. D is son of F who is brother of A. C is daughter of A. E is the sister of D. How is E related to C?',
       'a', 'hard',
       '{"a": "Cousin", "b": "Sister", "c": "Niece", "d": "Aunt"}',
       'multiple_choice', 1.0, 20, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;
    """

    # =========================================================================
    # 7. Reset sequences
    # =========================================================================
    execute "SELECT setval('subjects_id_seq', (SELECT MAX(id) FROM subjects));"
    execute "SELECT setval('topics_id_seq', (SELECT MAX(id) FROM topics));"
    execute "SELECT setval('qa_id_seq', (SELECT MAX(id) FROM qa));"
  end

  def down do
    # Remove aptitude questions
    execute "DELETE FROM qa WHERE topic_id IN (18, 19, 20);"
    # Remove aptitude topics
    execute "DELETE FROM topics WHERE id IN (18, 19, 20);"
    # Remove aptitude from curricula_subjects
    execute "DELETE FROM curricula_subjects WHERE subject_id = 7;"
    # Remove aptitude subject
    execute "DELETE FROM subjects WHERE id = 7;"
  end
end
