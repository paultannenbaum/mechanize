defmodule Mechanize.QueryTest do
  use ExUnit.Case, async: true
  alias Mechanize.Page.Element
  alias Mechanize.Query
  alias Mechanize.Test.Support.{ElementableFake1, ElementableFake2}

  import TestHelper

  doctest Mechanize.Query

  setup_all do
    stub_requests("/test/htdocs/query_test.html")
  end

  describe ".search" do
    test "return element list", %{page: page} do
      result = Query.search(page, ".spanish")

      assert is_list(result)
      Enum.each(result, fn e -> %Element{} = e end)
    end

    test "raise if page or element list is nil" do
      assert_raise ArgumentError, "page_or_fragment is nil", fn ->
        Query.search(nil, ".spanish")
      end
    end

    test "raise if selector is nil", %{page: page} do
      assert_raise ArgumentError, "selector is nil", fn ->
        Query.search(page, nil)
      end
    end

    test "empty page_or_fragment" do
      assert Query.search([], ".english") == []
    end

    test "if none matched return empty list", %{page: page} do
      assert Query.search(page, ".english") == []
    end

    test "match elements of a page by css selector", %{page: page} do
      assert page
             |> Query.search(".spanish")
             |> Enum.map(&Element.text/1) == ["Spain", "Chile", "Argentina"]
    end

    test "nested search", %{page: page} do
      assert page
             |> Query.search(".america")
             |> Query.search(".spanish")
             |> Enum.map(&Element.text/1) == ["Chile", "Argentina"]
    end

    test "match siblings in nested search", %{page: page} do
      assert page
             |> Query.search(".continent")
             |> Query.search(".portuguese")
             |> Enum.map(&Element.text/1) == ["Portugal", "Brazil"]
    end

    test "search elements returned by filter", %{page: page} do
      assert page
             |> Query.filter_out(".america")
             |> Query.search(".spanish")
             |> Enum.map(&Element.text/1) == ["Spain"]
    end
  end

  describe ".filter_out" do
    test "return element list", %{page: page} do
      assert is_list(Query.filter_out(page, ".europe"))
    end

    test "raise if parseable is nil" do
      assert_raise ArgumentError, "page_or_fragment is nil", fn ->
        Query.filter_out(nil, ".spanish")
      end
    end

    test "raise if selector is nil", %{page: page} do
      assert_raise ArgumentError, "selector is nil", fn ->
        Query.filter_out(page, nil)
      end
    end

    test "empty page_or_fragment" do
      assert Query.filter_out([], ".english") == []
    end

    test "if all matched return empty list", %{page: page} do
      assert Query.filter_out(page, "*") == []
    end

    test "returns elements of a page unmatched by css selector", %{page: page} do
      [expected] =
        """
          <!DOCTYPE html>
          <body>
          <div class="europe continent">
            <div class="portuguese">Portugal</div>
          </div>

          <div class="america continent">
            <div class="portuguese">Brazil</div>
          </div>
        </body>

        </html>
        """
        |> page.parser.parse_document()

      [result] = Query.filter_out(page, ".spanish")

      assert result.parser_node == expected
    end

    test "accepts single element returned by .search", %{page: page} do
      [expected] =
        """
          <div class="america continent">
            <div class="portuguese">Brazil</div>
          </div>
        """
        |> page.parser.parse_document()

      [result] =
        page
        |> Query.search(".america")
        |> Query.filter_out(".spanish")

      assert result.parser_node == expected
    end

    test "accepts many elements returned by .search", %{page: page} do
      expected =
        [
          ~s(<div class="europe continent"><div class="portuguese">Portugal</div></div>),
          ~s(<div class="america continent"><div class="portuguese">Brazil</div></div>)
        ]
        |> Enum.flat_map(fn html -> page.parser.parse_document(html) end)

      result =
        page
        |> Query.search(".continent")
        |> Query.filter_out(".spanish")
        |> Enum.map(& &1.parser_node)

      assert result == expected
    end
  end

  describe ".elements_with" do
    test "raise if parseable is nil" do
      assert_raise ArgumentError, "page_or_fragment is nil", fn ->
        Query.elements_with(nil, "div")
      end
    end

    test "raise if selector is nil", %{page: page} do
      assert_raise ArgumentError, "selector is nil", fn ->
        Query.elements_with(page, nil)
      end
    end

    test "select none by selector", %{page: page} do
      assert Query.elements_with(page, ".asia", class: "spanish") == []
    end

    test "select none by query", %{page: page} do
      assert Query.elements_with(page, ".america", class: "english") == []
    end

    test "select by css and query", %{page: page} do
      assert page
             |> Query.elements_with(".continent > *", class: "portuguese")
             |> Enum.map(&Element.text/1) == ["Portugal", "Brazil"]
    end
  end

  setup do
    fake_1a = %ElementableFake1{
      element: %Element{
        name: "elementable_fake_1",
        attrs: [{"value", "A"}, {"rel", "fake_1a"}, {"nill_attr", nil}, {"empty_attr", ""}],
        text: "ElementableFake 1A"
      }
    }

    fake_1b = %ElementableFake1{
      element: %Element{
        name: "elementable_fake_1",
        attrs: [{"value", "B"}, {"rel", "fake_1b"}],
        text: "ElementableFake1 1B"
      }
    }

    fake_2a = %ElementableFake2{
      element: %Element{
        name: "elementable_fake_2",
        attrs: [{"value", "A"}, {"rel", "fake_2a"}],
        text: "ElementableFake2 2A"
      }
    }

    {:ok, %{fake_1a: fake_1a, fake_1b: fake_1b, fake_2a: fake_2a}}
  end

  describe ".match_query?/2" do
    test "raise if element is nil" do
      assert_raise ArgumentError, "element is nil", fn ->
        Query.match_query?(nil, value: "A")
      end
    end

    test "raise if query is nil", %{fake_1a: fake_1a} do
      assert_raise ArgumentError, "query is nil", fn ->
        Query.match_query?(fake_1a, nil)
      end
    end

    test "raise if query has a nil value", %{fake_1a: fake_1a} do
      assert_raise ArgumentError, "query :value is nil", fn ->
        Query.match_query?(fake_1a, value: nil)
      end
    end

    test "empty query matches everything", %{
      fake_1a: fake_1a,
      fake_1b: fake_1b,
      fake_2a: fake_2a
    } do
      assert Query.match_query?(fake_1a, []) == true
      assert Query.match_query?(fake_1b, []) == true
      assert Query.match_query?(fake_2a, []) == true
    end

    test "match by index attribute" do
      assert Query.match_query?(%{index: 1}, 1) == true
    end

    test "does not match by index attribute" do
      assert Query.match_query?(%{index: 1}, 2) == false
    end

    test "does not match if index is not present" do
      assert Query.match_query?(%{value: 1}, 1) == false
    end

    test "present attributes match true", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: true) == true
    end

    test "absent attributes do not match true", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, absent_attr: true) == false
    end

    test "present attributes do not match false", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: false) == false
    end

    test "absent attributes match false", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, absent_attr: false) == true
    end

    test "attributes with empty string value matches empty string", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, empty_attr: "") == true
    end

    test "attributes matches list", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: ["A", "B"]) == true
    end

    test "attributes does not matches list", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: ["B", "C"]) == false
    end

    test "attributes does not matches an empty list", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: []) == false
    end

    test "attributes matches string", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: "A") == true
    end

    test "attribute doest not match string", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: "B") == false
    end

    test "absent attribute does not match string", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, absent_attr: "A") == false
    end

    test "attributes matches regexp", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: ~r/A/) == true
    end

    test "attribute doest not match regexp", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: ~r/B/) == false
    end

    test "absent attribute does not match regexp", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, absent_attr: ~r/A/) == false
    end

    test "match attribute chain by string", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: "A", rel: "fake_1a") == true
    end

    test "unmatch attribute chain by string", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: "A", rel: "wrong") == false
    end

    test "match attribute chain by regexp", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: ~r/A/, rel: ~r/fake_1a/) == true
    end

    test "unmatch attribute chain by regexp", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, value: ~r/A/, rel: ~r/wrong/) == false
    end

    test "raise if text query is nil", %{fake_1a: fake_1a} do
      assert_raise ArgumentError, "query :text is nil", fn ->
        Query.match_query?(fake_1a, text: nil)
      end
    end

    test "text matches a list", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, text: ["ElementableFake 1A", "ElementableFake 1B"]) ==
               true
    end

    test "text does not match a list", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, text: ["ElementableFake 2A", "ElementableFake 1B"]) ==
               false
    end

    test "text matches does not match an empty list", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, text: []) == false
    end

    test "text matches string", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, text: "ElementableFake 1A") == true
    end

    test "text matches string using shortcut", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, "ElementableFake 1A") == true
    end

    test "text does not match string", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, text: "wrong") == false
    end

    test "text match regexp", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, text: ~r/1A/) == true
    end

    test "text does not match regexp", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, text: ~r/wrong/) == false
    end

    test "match attribute and text chained", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, text: "ElementableFake 1A", rel: "fake_1a") == true
    end

    test "does not match attribute and text chained", %{fake_1a: fake_1a} do
      assert Query.match_query?(fake_1a, text: "ElementableFake 1A", rel: "wrong") == false
    end
  end

  describe ".match?/3" do
    test "raise if element is nil" do
      assert_raise ArgumentError, "element is nil", fn ->
        Query.match?(nil, ElementableFake1, value: "A")
      end
    end

    test "raise if types is nil", %{fake_1a: fake_1a} do
      assert_raise ArgumentError, "types is nil", fn ->
        Query.match?(fake_1a, nil, value: "A")
      end
    end

    test "raise if query is nil", %{fake_1a: fake_1a} do
      assert_raise ArgumentError, "query is nil", fn ->
        Query.match?(fake_1a, ElementableFake1, nil)
      end
    end

    test "matches type", %{fake_1a: fake_1a, fake_2a: fake_2a} do
      assert Query.match?(fake_1a, ElementableFake1, value: "A") == true
      assert Query.match?(fake_2a, ElementableFake1, value: "A") == false
    end

    test "matches with many types", %{fake_1a: fake_1a, fake_2a: fake_2a} do
      assert Query.match?(fake_1a, [ElementableFake1, ElementableFake2], value: "A") == true
      assert Query.match?(fake_2a, [ElementableFake1, ElementableFake2], value: "A") == true
    end

    test "matches query", %{fake_1a: fake_1a, fake_1b: fake_1b} do
      assert Query.match?(fake_1a, ElementableFake1, value: "A") == true
      assert Query.match?(fake_1b, ElementableFake1, value: "A") == false
    end
  end
end
