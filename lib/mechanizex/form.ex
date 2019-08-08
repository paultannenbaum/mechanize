defmodule Mechanizex.Form do
  alias Mechanizex.Page.Element
  alias Mechanizex.Form.{TextInput, DetachedField, Checkbox, ParameterizableField}
  alias Mechanizex.{Query, Request}
  import Mechanizex.Query, only: [query: 1]
  use Mechanizex.Form.{RadioButton, SubmitButton, Checkbox}

  @derive [Mechanizex.Page.Elementable]
  @enforce_keys [:element]
  defstruct element: nil,
            fields: []

  @type t :: %__MODULE__{
          element: Element.t(),
          fields: list()
        }

  @spec new(Element.t()) :: Form.t()
  def new(element) do
    %Mechanizex.Form{
      element: element,
      fields: parse_fields(element)
    }
  end

  defmodule FormNotUpdatedError do
    defexception [:message]
  end

  defmodule InconsistentFormError do
    defexception [:message]
  end

  def fill_field(form, field, with: value) do
    updated_form = update_field(form, field, value)
    if updated_form == form, do: add_field(form, field, value), else: updated_form
  end

  def update_field(form, field_name, value) do
    update_fields(form, fn field ->
      if field.name == field_name, do: %{field | value: value}, else: field
    end)
  end

  def add_field(form, field, value) do
    create_field(form, DetachedField.new(field, value))
  end

  def delete_field(form, field_name) do
    remove_fields(form, fn field -> field.name == field_name end)
  end

  def create_field(form, field) do
    Map.put(form, :fields, [field | form.fields])
  end

  def update_fields(form, fun) do
    %__MODULE__{form | fields: Enum.map(form.fields, fun)}
  end

  def update_fields(form, type, fun) when is_atom(type) do
    update_fields(form, [type], fun)
  end

  def update_fields(form, types, fun) do
    update_fields(form, fn field ->
      if field.__struct__ in types do
        fun.(field)
      else
        field
      end
    end)
  end

  def update_fields(form, types, criteria, fun) do
    update_fields(form, types, fn field ->
      if Query.match?(field, criteria) do
        fun.(field)
      else
        field
      end
    end)
  end

  def remove_fields(form, fun) do
    %__MODULE__{form | fields: Enum.reject(form.fields, fun)}
  end

  def fields(form) do
    form.fields
  end

  def fields_with(form, type, fun) when is_function(fun) do
    form.fields
    |> Stream.filter(&(type == &1.__struct__))
    |> Enum.filter(fun)
  end

  def fields_with(form, type, criteria) do
    form.fields
    |> Stream.filter(&(type == &1.__struct__))
    |> Enum.filter(query(criteria))
  end

  defdelegate check_checkboxes!(form, criteria), to: __MODULE__, as: :check_checkbox!

  def check_checkbox!(form, criteria) do
    case check_checkbox(form, criteria) do
      {:ok, form} -> form
      {:error, error} -> raise error
    end
  end

  defdelegate check_checkboxes(form, criteria), to: __MODULE__, as: :check_checkbox

  def check_checkbox(form, criteria) do
    form
    |> Checkbox.check(criteria)
    |> assert_form_updated(form, "Can't check checkbox with criteria #{inspect(criteria)}, it probably does not exist")
  end

  defdelegate uncheck_checkboxes!(form, criteria), to: __MODULE__, as: :uncheck_checkbox!

  def uncheck_checkbox!(form, criteria) do
    case uncheck_checkbox(form, criteria) do
      {:ok, form} -> form
      {:error, error} -> raise error
    end
  end

  defdelegate uncheck_checkboxes(form, criteria), to: __MODULE__, as: :uncheck_checkbox

  def uncheck_checkbox(form, criteria) do
    form
    |> Checkbox.uncheck(criteria)
    |> assert_form_updated(
      form,
      "Can't uncheck checkbox with criteria #{inspect(criteria)}, it probably does not exist"
    )
  end

  defdelegate check_radio_buttons!(form, criteria), to: __MODULE__, as: :check_radio_button!

  def check_radio_button!(form, criteria) do
    case check_radio_button(form, criteria) do
      {:ok, form} -> form
      {:error, error} -> raise error
    end
  end

  defdelegate check_radio_buttons(form, criteria), to: __MODULE__, as: :check_radio_button

  def check_radio_button(form, criteria) do
    new_form = RadioButton.check(form, criteria)

    with {:ok, new_form} <- assert_single_radio_in_group_checked(new_form),
         {:ok, new_form} <-
           assert_form_updated(
             new_form,
             form,
             "Can't check radio button with criteria #{inspect(criteria)}, it probably does not exist"
           ),
         do: {:ok, new_form}
  end

  defdelegate uncheck_radio_buttons!(form, criteria), to: __MODULE__, as: :uncheck_radio_button!

  def uncheck_radio_button!(form, criteria) do
    case uncheck_radio_button(form, criteria) do
      {:ok, form} -> form
      {:error, error} -> raise error
    end
  end

  defdelegate uncheck_radio_buttons(form, criteria), to: __MODULE__, as: :uncheck_radio_button

  def uncheck_radio_button(form, criteria) do
    form
    |> RadioButton.uncheck(criteria)
    |> assert_form_updated(
      form,
      "Can't uncheck radio button with criteria #{inspect(criteria)}, it probably does not exist"
    )
  end

  defdelegate click_button(form, criteria), to: SubmitButton, as: :click

  def click_button!(form, criteria) do
    case click_button(form, criteria) do
      {:ok, page} -> page
      {:error, error} -> raise error
    end
  end

  defp assert_form_updated(new_form, old_form, message) do
    if new_form.fields != old_form.fields do
      {:ok, new_form}
    else
      {:error, %FormNotUpdatedError{message: message}}
    end
  end

  defp assert_single_radio_in_group_checked(form) do
    radio_groups =
      form
      |> radio_buttons_with(fn radio -> radio.checked end)
      |> Enum.group_by(&Element.attr(&1, :name))
      |> Enum.filter(fn {_, radios_checked} -> length(radios_checked) > 1 end)

    if Enum.empty?(radio_groups) do
      {:ok, form}
    else
      group_names =
        radio_groups
        |> Enum.map(fn {group_name, _} -> group_name end)
        |> Enum.join(",")

      {:error, %InconsistentFormError{message: "Multiple radio buttons with same name (#{group_names}) are checked"}}
    end
  end

  def submit(form, button \\ nil) do
    Mechanizex.Agent.request(agent(form), %Request{
      method: method(form),
      url: action_url(form),
      params: params(form.fields, button)
    })
  end

  defp method(form) do
    method =
      form
      |> Element.attr(:method)
      |> Kernel.||("")
      |> String.trim()
      |> String.downcase()

    if method == "post", do: :post, else: :get
  end

  defp action_url(form) do
    form
    |> Element.attr(:action)
    |> Kernel.||("")
    |> String.trim()
    |> (&URI.merge(form.element.page.request.url, &1)).()
    |> URI.to_string()
  end

  defp params(fields, button) do
    fields
    |> Enum.reject(&match?(%SubmitButton{}, &1))
    |> maybe_add_submit_button(button)
    |> Enum.reject(fn f -> Element.attr_present?(f, :disabled) or f.name == nil end)
    |> Enum.flat_map(&ParameterizableField.to_param/1)
  end

  defp maybe_add_submit_button(params, nil), do: params
  defp maybe_add_submit_button(params, button), do: [button | params]

  defp agent(form) do
    form.element.page.agent
  end

  defp parse_fields(element) do
    element
    |> Query.search("input, textarea, button")
    |> Enum.map(&create_field/1)
    |> Enum.reject(&is_nil/1)
  end

  defp create_field(el) do
    name = Element.name(el)
    type = Element.attr(el, :type, normalize: true)

    cond do
      type == "reset" ->
        nil

      name == "button" and (type == "submit" or type == nil or type == "") ->
        SubmitButton.new(el)

      name == "input" and type == "radio" ->
        RadioButton.new(el)

      name == "input" and type == "checkbox" ->
        Checkbox.new(el)

      name == "input" and (type == "submit" or type == "image") ->
        SubmitButton.new(el)

      name == "textarea" or name == "input" ->
        TextInput.new(el)

      true ->
        nil
    end
  end
end
