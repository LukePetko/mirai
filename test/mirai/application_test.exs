defmodule Mirai.ApplicationTest do
  use ExUnit.Case, async: true

  test "finds automation files recursively with shared modules first" do
    root =
      Path.join(
        System.tmp_dir!(),
        "mirai-automations-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)

    files = [
      "relay/kitchen_led.ex",
      "shared/actions.ex",
      "top_level.ex",
      "relay/README.md"
    ]

    Enum.each(files, fn relative_path ->
      path = Path.join(root, relative_path)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "")
    end)

    assert Mirai.Application.automation_files(root) == [
             Path.join(root, "shared/actions.ex"),
             Path.join(root, "relay/kitchen_led.ex"),
             Path.join(root, "top_level.ex")
           ]
  end

  test "returns no automation files for a missing directory" do
    missing =
      Path.join(
        System.tmp_dir!(),
        "missing-mirai-automations-#{System.unique_integer([:positive])}"
      )

    assert Mirai.Application.automation_files(missing) == []
  end
end
