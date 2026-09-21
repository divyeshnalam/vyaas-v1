defmodule VyaasaCampus.AI.MiniProject.ScoringTest do
  use ExUnit.Case, async: true

  alias VyaasaCampus.AI.MiniProject.Scoring

  describe "fuse_metric/2 — asymmetric fusion" do
    test "cannot defend what was written (viva < artifact) scales down" do
      assert Scoring.fuse_metric(8, 6) == 4.8
      assert Scoring.fuse_metric(10, 0) == 0.0
      assert Scoring.fuse_metric(10, 6) == 6.0
    end

    test "defends more than written (viva >= artifact) gives modest bonus" do
      assert Scoring.fuse_metric(6, 8) == 7.0
      assert Scoring.fuse_metric(0, 10) == 5.0
      assert Scoring.fuse_metric(5, 5) == 5.0
    end
  end

  describe "apply_noise_floor/2" do
    test "single bad answer is floored at 2" do
      assert Scoring.apply_noise_floor(1.0, [1, 5]) == 2.0
    end

    test "two independently low answers keep the low score" do
      assert Scoring.apply_noise_floor(1.0, [1, 2]) == 1.0
    end

    test "scores >= 2 are untouched" do
      assert Scoring.apply_noise_floor(3.0, [3, 3]) == 3.0
    end
  end

  describe "aggregate_viva_per_metric/1" do
    test "averages per metric and applies noise floor" do
      results = [
        %{"metric" => "D1", "score" => 8},
        %{"metric" => "D1", "score" => 6},
        %{"metric" => "D2", "score" => 1}
      ]

      agg = Scoring.aggregate_viva_per_metric(results)
      assert agg["D1"] == 7.0
      # D2 single score of 1 (one question) -> noise floor lifts to 2.0
      assert agg["D2"] == 2.0
      # metric with no answers -> 0.0
      assert agg["D3"] == 0.0
    end
  end

  describe "compute_authenticity_gate/3" do
    test "all small gaps -> genuine" do
      c = %{"D1" => 8, "D2" => 8, "D3" => 8, "D4" => 8}
      v = %{"D1" => 7.5, "D2" => 8, "D3" => 7, "D4" => 8}
      assert Scoring.compute_authenticity_gate(c, v, false) == "genuine"
    end

    test "one weak metric -> clustered_gaps" do
      c = %{"D1" => 8, "D2" => 8, "D3" => 8, "D4" => 8}
      v = %{"D1" => 3, "D2" => 8, "D3" => 8, "D4" => 8}
      assert Scoring.compute_authenticity_gate(c, v, false) == "clustered_gaps"
    end

    test "most metrics weak -> broad_gaps" do
      c = %{"D1" => 9, "D2" => 9, "D3" => 9, "D4" => 9}
      v = %{"D1" => 3, "D2" => 3, "D3" => 8, "D4" => 8}
      assert Scoring.compute_authenticity_gate(c, v, false) == "broad_gaps"
    end

    test "contradiction flag -> contradicts" do
      assert Scoring.compute_authenticity_gate(%{}, %{}, true) == "contradicts"
    end
  end

  describe "compute_final_score/3" do
    test "genuine performance stands" do
      c = %{"D1" => 8, "D2" => 8, "D3" => 8, "D4" => 8, "D5" => 8}
      v = %{"D1" => 8, "D2" => 8, "D3" => 8, "D4" => 8, "D5" => 8}
      r = Scoring.compute_final_score(c, v, false)
      assert r["final_score"] == 80
      assert r["authenticity"] == "genuine"
      assert r["band"] == "Strong"
    end

    test "broad gaps caps the composite at 54" do
      c = %{"D1" => 10, "D2" => 10, "D3" => 10, "D4" => 10, "D5" => 6}
      v = %{"D1" => 6, "D2" => 6, "D3" => 6, "D4" => 6, "D5" => 6}
      r = Scoring.compute_final_score(c, v, false)
      assert r["composite_raw"] == 60
      assert r["final_score"] == 54
      assert r["authenticity"] == "broad_gaps"
      assert r["band"] == "Insufficient"
    end

    test "contradiction caps at 39 and flags review" do
      c = %{"D1" => 9, "D2" => 9, "D3" => 9, "D4" => 9, "D5" => 9}
      v = %{"D1" => 9, "D2" => 9, "D3" => 9, "D4" => 9, "D5" => 9}
      r = Scoring.compute_final_score(c, v, true)
      assert r["final_score"] == 39
      assert r["authenticity"] == "contradicts"
    end
  end

  describe "score_to_band/1" do
    test "band thresholds" do
      assert Scoring.score_to_band(90) == "Outstanding"
      assert Scoring.score_to_band(70) == "Strong"
      assert Scoring.score_to_band(55) == "Developing"
      assert Scoring.score_to_band(40) == "Insufficient"
      assert Scoring.score_to_band(10) == "Not ready"
    end
  end

  describe "apply_timing_to_result/4 (soft mode)" do
    test "fast submit reinforces an existing broad-gaps concern" do
      base = %{"final_score" => 50, "band" => "Insufficient", "authenticity" => "broad_gaps", "gate_note" => "Concern."}
      r = Scoring.apply_timing_to_result(base, "fast", 10, 90)
      assert r["final_score"] == 50
      assert r["gate_note"] =~ "reinforces"
      assert r["timing"]["flag"] == "fast"
    end

    test "over submit is informational only" do
      base = %{"final_score" => 72, "band" => "Strong", "authenticity" => "genuine", "gate_note" => ""}
      r = Scoring.apply_timing_to_result(base, "over", 130, 90)
      assert r["final_score"] == 72
      assert r["timing_note"] =~ "informational only"
    end
  end
end
