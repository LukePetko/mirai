defmodule Mirai.Event do
  @moduledoc """
  Structure representing a normalized event.
  """

  @type event_source :: :home_assistant | :mqtt | :rest
  @type event_type :: :state_changed | :service_called | :automation_triggered | :unknown

  @type t :: %__MODULE__{
          id: String.t(),
          source: event_source(),
          type: event_type(),
          timestamp: DateTime.t(),
          entity_id: String.t() | nil,
          domain: String.t() | nil,
          old_state: map() | nil,
          new_state: map() | nil,
          attributes: map(),
          context: map(),
          event: map()
        }

  @enforce_keys [:id, :source, :type, :timestamp]
  defstruct [
    :id,
    :source,
    :type,
    :timestamp,
    :entity_id,
    :domain,
    :old_state,
    :new_state,
    :attributes,
    :context,
    :event
  ]

  def new(params) do
    struct!(__MODULE__, params)
  end

  def extract_domain(entity_id) when is_binary(entity_id) do
    entity_id
    |> String.split(".", parts: 2)
    |> List.first()
  end

  def extract_domain(_), do: nil
end
