defmodule Kaska.TaskBodyTest do
  use ExUnit.Case, async: true

  alias Kaska.TaskBody

  describe "from_markdown/1" do
    test "empty and non-string inputs return the empty doc" do
      assert TaskBody.from_markdown("") == TaskBody.empty_doc()
      assert TaskBody.from_markdown(nil) == TaskBody.empty_doc()
      assert TaskBody.from_markdown(42) == TaskBody.empty_doc()
    end

    test "paragraph with inline marks" do
      doc = TaskBody.from_markdown("A **b** *i* ~~s~~ `c` [l](https://x.io)")

      assert %{
               "type" => "doc",
               "content" => [%{"type" => "paragraph", "content" => content}]
             } = doc

      assert %{"type" => "text", "text" => "b", "marks" => [%{"type" => "bold"}]} in content
      assert %{"type" => "text", "text" => "i", "marks" => [%{"type" => "italic"}]} in content
      assert %{"type" => "text", "text" => "s", "marks" => [%{"type" => "strike"}]} in content
      assert %{"type" => "text", "text" => "c", "marks" => [%{"type" => "code"}]} in content

      assert %{
               "type" => "text",
               "text" => "l",
               "marks" => [%{"type" => "link", "attrs" => %{"href" => "https://x.io"}}]
             } in content
    end

    test "heading levels are clamped to the h2/h3 editor schema" do
      assert %{"content" => [%{"type" => "heading", "attrs" => %{"level" => 2}}]} =
               TaskBody.from_markdown("# top")

      assert %{"content" => [%{"type" => "heading", "attrs" => %{"level" => 3}}]} =
               TaskBody.from_markdown("#### deep")
    end

    test "code block keeps language and literal text" do
      doc = TaskBody.from_markdown("```elixir\nIO.puts(1)\n```")

      assert %{
               "content" => [
                 %{
                   "type" => "codeBlock",
                   "attrs" => %{"language" => "elixir"},
                   "content" => [%{"type" => "text", "text" => "IO.puts(1)"}]
                 }
               ]
             } = doc
    end

    test "bullet and ordered lists" do
      assert %{"content" => [%{"type" => "bulletList", "content" => items}]} =
               TaskBody.from_markdown("- a\n- b")

      assert length(items) == 2

      assert %{"content" => [%{"type" => "orderedList", "attrs" => %{"start" => 1}}]} =
               TaskBody.from_markdown("1. a\n2. b")
    end

    test "adjacent text fragments are merged" do
      assert %{"content" => [%{"type" => "paragraph", "content" => [single]}]} =
               TaskBody.from_markdown("one\ntwo")

      assert single == %{"type" => "text", "text" => "one two"}
    end
  end

  describe "to_markdown/1" do
    test "nil and malformed docs render to empty string" do
      assert TaskBody.to_markdown(nil) == ""
      assert TaskBody.to_markdown(%{"foo" => "bar"}) == ""
    end

    test "renders marks and a link" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "bold", "marks" => [%{"type" => "bold"}]},
              %{"type" => "text", "text" => " plain "},
              %{
                "type" => "text",
                "text" => "site",
                "marks" => [%{"type" => "link", "attrs" => %{"href" => "https://x.io"}}]
              }
            ]
          }
        ]
      }

      assert TaskBody.to_markdown(doc) == "**bold** plain [site](https://x.io)"
    end
  end

  describe "API body representation" do
    test "normalize_format defaults to markdown and only json opts out" do
      assert TaskBody.normalize_format(nil) == :markdown
      assert TaskBody.normalize_format("md") == :markdown
      assert TaskBody.normalize_format("markdown") == :markdown
      assert TaskBody.normalize_format("bogus") == :markdown
      assert TaskBody.normalize_format("json") == :json
      assert TaskBody.normalize_format(:json) == :json
    end

    test "body_view renders markdown or raw doc per format" do
      doc = TaskBody.from_markdown("## Title")

      assert TaskBody.body_view(doc, :markdown) == "## Title"
      assert TaskBody.body_view(doc, :json) == doc
    end
  end

  describe "round trip" do
    test "markdown survives a doc round trip" do
      md =
        Enum.join(
          [
            "## Heading",
            "",
            "Para with **bold**, *italic*, `code`, [link](https://x.io).",
            "",
            "- one",
            "- two",
            "",
            "1. first",
            "2. second",
            "",
            "```elixir",
            "IO.puts(1)",
            "```",
            "",
            "---"
          ],
          "\n"
        )

      round_tripped = md |> TaskBody.from_markdown() |> TaskBody.to_markdown()

      assert round_tripped == md
    end
  end
end
