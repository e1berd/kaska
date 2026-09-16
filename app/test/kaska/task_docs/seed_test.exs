defmodule Kaska.TaskDocs.SeedTest do
  use ExUnit.Case, async: true

  alias Kaska.TaskBody
  alias Kaska.TaskDocs.Seed

  defp fragment_string(doc) do
    doc |> Yex.Doc.get_xml_fragment("default") |> Yex.XmlFragment.to_string()
  end

  test "no-ops on a blank body_doc" do
    doc = Yex.Doc.new()
    refute Seed.seed(doc, TaskBody.empty_doc())
    assert fragment_string(doc) == ""
  end

  test "no-ops on nil" do
    doc = Yex.Doc.new()
    refute Seed.seed(doc, nil)
    assert fragment_string(doc) == ""
  end

  test "does not overwrite a fragment that already has content" do
    doc = Yex.Doc.new()
    fragment = Yex.Doc.get_xml_fragment(doc, "default")
    Yex.XmlFragment.push(fragment, Yex.XmlElementPrelim.new("paragraph", [], %{}))

    refute Seed.seed(doc, TaskBody.from_markdown("hello"))
    assert fragment_string(doc) == "<paragraph></paragraph>"
  end

  test "seeds paragraphs, marks and links from markdown-derived body_doc" do
    doc = Yex.Doc.new()
    body_doc = TaskBody.from_markdown("A **b** *i* ~~s~~ `c` [l](https://x.io)")

    assert Seed.seed(doc, body_doc)

    fragment = Yex.Doc.get_xml_fragment(doc, "default")
    assert Yex.XmlFragment.length(fragment) == 1

    {:ok, paragraph} = Yex.XmlFragment.fetch(fragment, 0)
    assert Yex.XmlElement.get_tag(paragraph) == "paragraph"

    {:ok, text} = Yex.XmlElement.fetch(paragraph, 0)
    delta = Yex.XmlText.to_delta(text)

    assert %{insert: "b", attributes: %{"bold" => true}} in delta
    assert %{insert: "i", attributes: %{"italic" => true}} in delta
    assert %{insert: "s", attributes: %{"strike" => true}} in delta
    assert %{insert: "c", attributes: %{"code" => true}} in delta

    assert %{insert: "l", attributes: %{"link" => %{"href" => "https://x.io"}}} in delta
  end

  test "seeds heading level and list attrs as real values, not strings" do
    doc = Yex.Doc.new()
    body_doc = TaskBody.from_markdown("## Title\n\n1. one\n2. two")

    assert Seed.seed(doc, body_doc)

    fragment = Yex.Doc.get_xml_fragment(doc, "default")
    {:ok, heading} = Yex.XmlFragment.fetch(fragment, 0)
    assert Yex.XmlElement.get_tag(heading) == "heading"
    assert Yex.XmlElement.get_attribute(heading, "level") == 2.0

    {:ok, ordered_list} = Yex.XmlFragment.fetch(fragment, 1)
    assert Yex.XmlElement.get_tag(ordered_list) == "orderedList"
    assert Yex.XmlElement.get_attribute(ordered_list, "start") == 1.0
    assert Yex.XmlElement.length(ordered_list) == 2
  end

  test "keeps block order across headings, lists and paragraphs" do
    doc = Yex.Doc.new()
    body_doc = TaskBody.from_markdown("# Intro\n\nSome text\n\n- one\n- two")

    assert Seed.seed(doc, body_doc)

    fragment = Yex.Doc.get_xml_fragment(doc, "default")
    tags = fragment |> Yex.XmlFragment.children() |> Enum.map(&Yex.XmlElement.get_tag/1)

    assert tags == ["heading", "paragraph", "bulletList"]
  end
end
