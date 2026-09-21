defmodule VyaasaCampusWeb.Admin.QuestionBankLiveTest do
  @moduledoc """
  Uploading questions for one specialization must never touch another branch's
  question pool — that pool is what `Contexts.Assessments` reads to build a
  student's exam, so cross-linking here means the wrong subject content reaches
  a live exam.

  Regression coverage for the bug where uploading via a specialization with no
  existing `curricula` row (e.g. an MBA specialization, freshly seeded) fell
  back to linking the new subject into EVERY branch, including "Computer
  Science" — reported after a real Finance upload showed up there.

  Also covers a second, related bug: a branch used to be created per-DEGREE
  (all of MBA's specializations sharing one "MBA" branch), which hid every
  specialization but one from the admin "Branches" tab (it groups by branch).
  A branch is now per-SPECIALIZATION, scoped by (name, qualification_id) —
  not name alone, since two different degrees can share a specialization name
  (e.g. both MBA and B.Tech have an "Information Technology" specialization),
  and matching on name alone would silently merge their question pools.
  """

  use VyaasaCampusWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VyaasaCampus.Contexts.Academics
  alias VyaasaCampus.Guardian
  alias VyaasaCampus.Repo
  alias VyaasaCampus.Schema.Platform.AdminUser

  setup %{conn: conn} do
    admin =
      Repo.get_by(AdminUser, email: "qb-test@vyaasa.test") ||
        Repo.insert!(%AdminUser{
          email: "qb-test@vyaasa.test",
          encrypted_password: Bcrypt.hash_pwd_salt("password123"),
          first_name: "QB",
          last_name: "Tester",
          role: "super_admin",
          status: "active"
        })

    # Fully isolated degree/specialization so this test can never collide with
    # (or pollute) real MBA/Finance data.
    suffix = System.unique_integer([:positive])
    {:ok, degree} = Academics.create_degree(%{"name" => "QB Test Degree #{suffix}", "code" => "QBD#{suffix}"})
    {:ok, spec} = Academics.create_specialization(%{"name" => "QB Test Spec #{suffix}", "code" => "QBS#{suffix}", "degree_id" => degree.id})

    {_cs_branch_id, cs_curricula_id} = an_existing_branch_and_curricula()
    cs_links_before = curricula_subject_count(cs_curricula_id)

    {:ok, token, _} = Guardian.encode_and_sign(admin)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:auth_token, token)

    on_exit(fn -> cleanup(degree.id, spec.id) end)

    {:ok, conn: conn, degree: degree, spec: spec, cs_curricula_id: cs_curricula_id, cs_links_before: cs_links_before}
  end

  test "an upload for a fresh specialization creates its own curricula row and never links into another branch",
       %{conn: conn, degree: degree, spec: spec, cs_curricula_id: cs_curricula_id, cs_links_before: cs_links_before} do
    {:ok, view, _html} = live(conn, ~p"/admin/question-bank")

    view |> element("form[phx-change='select_degree']") |> render_change(%{"degree_id" => degree.id})
    view |> element("form[phx-change='select_spec']") |> render_change(%{"spec_id" => spec.id})

    archive_path = build_fixture_zip()

    avatar =
      file_input(view, "#upload-form", :question_zip, [
        %{
          last_modified: System.system_time(:millisecond),
          name: "upload.zip",
          content: File.read!(archive_path),
          type: "application/zip"
        }
      ])

    render_upload(avatar, "upload.zip")
    view |> form("#upload-form") |> render_submit()

    File.rm(archive_path)

    # The subject landed under the right specialization.
    {:ok, %{rows: [[subject_id]]}} =
      Repo.query("SELECT id FROM public.subjects WHERE name = 'TestSubject' AND specialization_id = $1",
        [Ecto.UUID.dump!(spec.id)])

    # A curricula row now exists, scoped to this specialization — not the CS one.
    {:ok, %{rows: [[curricula_id, branch_id]]}} =
      Repo.query("SELECT id, branch_id FROM public.curricula WHERE specialization_id = $1", [Ecto.UUID.dump!(spec.id)])

    refute curricula_id == cs_curricula_id

    # curricula_subjects links the new subject ONLY to its own curricula...
    {:ok, %{rows: own_links}} =
      Repo.query("SELECT curricula_id FROM public.curricula_subjects WHERE subject_id = $1", [subject_id])

    assert Enum.map(own_links, &List.first/1) == [curricula_id]

    # ...and Computer Science's link count is completely unaffected.
    assert curricula_subject_count(cs_curricula_id) == cs_links_before

    # The branch is named after the SPECIALIZATION (not the degree) and has a
    # qualification set — otherwise it's invisible to load_branch_stats/0's
    # INNER JOIN against qualifications, i.e. it wouldn't render at all.
    {:ok, %{rows: [[branch_name, qualification_id]]}} =
      Repo.query("SELECT name, qualification_id FROM public.branches WHERE id = $1", [branch_id])

    assert branch_name == spec.name
    refute is_nil(qualification_id)

    {:ok, %{rows: [[qualification_name]]}} =
      Repo.query("SELECT name FROM public.qualifications WHERE id = $1", [qualification_id])

    assert qualification_name == degree.name
  end

  test "two degrees sharing a specialization name get separate branches, not one shared pool",
       %{conn: conn} do
    suffix = System.unique_integer([:positive])
    shared_name = "Shared Spec Name #{suffix}"

    {:ok, degree_a} = Academics.create_degree(%{"name" => "QB Degree A #{suffix}", "code" => "QBA#{suffix}"})
    {:ok, spec_a} = Academics.create_specialization(%{"name" => shared_name, "code" => "QBAS#{suffix}", "degree_id" => degree_a.id})
    {:ok, degree_b} = Academics.create_degree(%{"name" => "QB Degree B #{suffix}", "code" => "QBB#{suffix}"})
    {:ok, spec_b} = Academics.create_specialization(%{"name" => shared_name, "code" => "QBBS#{suffix}", "degree_id" => degree_b.id})

    on_exit(fn ->
      cleanup(degree_a.id, spec_a.id)
      cleanup(degree_b.id, spec_b.id)
    end)

    {:ok, conn: conn} = auth_conn(conn)

    upload_one_subject(conn, degree_a, spec_a, "SubjectA")
    upload_one_subject(conn, degree_b, spec_b, "SubjectB")

    {:ok, %{rows: [[branch_a]]}} =
      Repo.query("SELECT branch_id FROM public.curricula WHERE specialization_id = $1", [Ecto.UUID.dump!(spec_a.id)])

    {:ok, %{rows: [[branch_b]]}} =
      Repo.query("SELECT branch_id FROM public.curricula WHERE specialization_id = $1", [Ecto.UUID.dump!(spec_b.id)])

    refute branch_a == branch_b, "two unrelated degrees' same-named specialization must not share a branch"
  end

  defp auth_conn(conn) do
    admin =
      Repo.get_by(AdminUser, email: "qb-test@vyaasa.test") ||
        Repo.insert!(%AdminUser{
          email: "qb-test@vyaasa.test",
          encrypted_password: Bcrypt.hash_pwd_salt("password123"),
          first_name: "QB",
          last_name: "Tester",
          role: "super_admin",
          status: "active"
        })

    {:ok, token, _} = Guardian.encode_and_sign(admin)

    {:ok,
     conn:
       conn
       |> Plug.Test.init_test_session(%{})
       |> Plug.Conn.put_session(:auth_token, token)}
  end

  defp upload_one_subject(conn, degree, spec, subject_name) do
    {:ok, view, _html} = live(conn, ~p"/admin/question-bank")

    view |> element("form[phx-change='select_degree']") |> render_change(%{"degree_id" => degree.id})
    view |> element("form[phx-change='select_spec']") |> render_change(%{"spec_id" => spec.id})

    archive_path = build_fixture_zip(subject_name)

    avatar =
      file_input(view, "#upload-form", :question_zip, [
        %{
          last_modified: System.system_time(:millisecond),
          name: "upload.zip",
          content: File.read!(archive_path),
          type: "application/zip"
        }
      ])

    render_upload(avatar, "upload.zip")
    view |> form("#upload-form") |> render_submit()
    File.rm(archive_path)
  end

  defp an_existing_branch_and_curricula do
    {:ok, %{rows: [[branch_id]]}} =
      Repo.query("SELECT id FROM public.branches WHERE name = 'Computer Science' LIMIT 1")

    {:ok, %{rows: [[curricula_id]]}} =
      Repo.query("SELECT id FROM public.curricula WHERE branch_id = $1 LIMIT 1", [branch_id])

    {branch_id, curricula_id}
  end

  defp curricula_subject_count(curricula_id) do
    {:ok, %{rows: [[count]]}} =
      Repo.query("SELECT count(*) FROM public.curricula_subjects WHERE curricula_id = $1", [curricula_id])

    count
  end

  # Root/<subject_name>/TestChapter.txt — matches the parser's expected depth
  # and JSON shape (question/options/correct_answer/difficulty/topic).
  defp build_fixture_zip(subject_name \\ "TestSubject") do
    question = %{
      "question" => "What is 2 + 2?",
      "options" => ["3", "4", "5", "6"],
      "correct_answer" => "4",
      "difficulty" => "easy",
      "topic" => "Arithmetic"
    }

    content = Jason.encode!([question])
    zip_path = Path.join(System.tmp_dir!(), "qb_fixture_#{System.unique_integer([:positive])}.zip")

    {:ok, _} =
      :zip.create(
        String.to_charlist(zip_path),
        [{String.to_charlist("Root/#{subject_name}/TestChapter.txt"), content}]
      )

    zip_path
  end

  defp cleanup(degree_id, spec_id) do
    {:ok, spec_uuid} = Ecto.UUID.dump(spec_id)

    Repo.query("""
      DELETE FROM public.qa WHERE topic_id IN (
        SELECT t.id FROM public.topics t
        JOIN public.subjects s ON s.id = t.subject_id
        WHERE s.specialization_id = $1
      )
    """, [spec_uuid])

    Repo.query("""
      DELETE FROM public.topics WHERE subject_id IN (
        SELECT id FROM public.subjects WHERE specialization_id = $1
      )
    """, [spec_uuid])

    Repo.query("""
      DELETE FROM public.chapters WHERE subject_id IN (
        SELECT id FROM public.subjects WHERE specialization_id = $1
      )
    """, [spec_uuid])

    Repo.query("DELETE FROM public.curricula_subjects WHERE subject_id IN (SELECT id FROM public.subjects WHERE specialization_id = $1)", [spec_uuid])
    Repo.query("DELETE FROM public.subjects WHERE specialization_id = $1", [spec_uuid])

    {:ok, %{rows: curricula_rows}} = Repo.query("SELECT id, branch_id FROM public.curricula WHERE specialization_id = $1", [spec_uuid])
    Repo.query("DELETE FROM public.curricula WHERE specialization_id = $1", [spec_uuid])

    for [_cid, branch_id] <- curricula_rows do
      Repo.query("DELETE FROM public.branches WHERE id = $1", [branch_id])
    end

    Repo.query("DELETE FROM public.specializations WHERE id = $1", [spec_uuid])
    Repo.query("DELETE FROM public.degrees WHERE id = $1", [Ecto.UUID.dump!(degree_id)])
  end
end
