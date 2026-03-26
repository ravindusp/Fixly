defmodule Fixly.Timezones do
  @moduledoc "Timezone data with GMT offsets and map coordinates for the timezone selector."

  @timezones [
    %{id: "Pacific/Midway", label: "GMT-11:00", city: "Midway Island", offset: -11, x: 30, y: 195},
    %{id: "Pacific/Honolulu", label: "GMT-10:00", city: "Honolulu", offset: -10, x: 49, y: 191},
    %{id: "America/Anchorage", label: "GMT-09:00", city: "Anchorage", offset: -9, x: 67, y: 80},
    %{id: "America/Los_Angeles", label: "GMT-08:00", city: "Los Angeles", offset: -8, x: 137, y: 155},
    %{id: "America/Denver", label: "GMT-07:00", city: "Denver", offset: -7, x: 167, y: 140},
    %{id: "America/Chicago", label: "GMT-06:00", city: "Chicago", offset: -6, x: 205, y: 134},
    %{id: "America/New_York", label: "GMT-05:00", city: "New York", offset: -5, x: 236, y: 137},
    %{id: "America/Santiago", label: "GMT-04:00", city: "Santiago", offset: -4, x: 262, y: 315},
    %{id: "America/Sao_Paulo", label: "GMT-03:00", city: "Sao Paulo", offset: -3, x: 296, y: 302},
    %{id: "Atlantic/South_Georgia", label: "GMT-02:00", city: "Mid-Atlantic", offset: -2, x: 350, y: 270},
    %{id: "Atlantic/Azores", label: "GMT-01:00", city: "Azores", offset: -1, x: 375, y: 138},
    %{id: "Europe/London", label: "GMT+00:00", city: "London", offset: 0, x: 400, y: 107},
    %{id: "Europe/Paris", label: "GMT+01:00", city: "Paris", offset: 1, x: 407, y: 114},
    %{id: "Europe/Berlin", label: "GMT+01:00", city: "Berlin", offset: 1, x: 418, y: 104},
    %{id: "Africa/Cairo", label: "GMT+02:00", city: "Cairo", offset: 2, x: 469, y: 133},
    %{id: "Europe/Moscow", label: "GMT+03:00", city: "Moscow", offset: 3, x: 483, y: 76},
    %{id: "Africa/Nairobi", label: "GMT+03:00", city: "Nairobi", offset: 3, x: 482, y: 215},
    %{id: "Asia/Tehran", label: "GMT+03:30", city: "Tehran", offset: 3.5, x: 514, y: 121},
    %{id: "Asia/Dubai", label: "GMT+04:00", city: "Dubai", offset: 4, x: 523, y: 155},
    %{id: "Asia/Kabul", label: "GMT+04:30", city: "Kabul", offset: 4.5, x: 544, y: 131},
    %{id: "Asia/Karachi", label: "GMT+05:00", city: "Karachi", offset: 5, x: 549, y: 155},
    %{id: "Asia/Colombo", label: "GMT+05:30", city: "Colombo", offset: 5.5, x: 577, y: 231},
    %{id: "Asia/Kolkata", label: "GMT+05:30", city: "Mumbai", offset: 5.5, x: 562, y: 175},
    %{id: "Asia/Kathmandu", label: "GMT+05:45", city: "Kathmandu", offset: 5.75, x: 589, y: 152},
    %{id: "Asia/Dhaka", label: "GMT+06:00", city: "Dhaka", offset: 6, x: 601, y: 160},
    %{id: "Asia/Yangon", label: "GMT+06:30", city: "Yangon", offset: 6.5, x: 612, y: 178},
    %{id: "Asia/Bangkok", label: "GMT+07:00", city: "Bangkok", offset: 7, x: 623, y: 186},
    %{id: "Asia/Singapore", label: "GMT+08:00", city: "Singapore", offset: 8, x: 631, y: 222},
    %{id: "Asia/Shanghai", label: "GMT+08:00", city: "Beijing", offset: 8, x: 659, y: 134},
    %{id: "Asia/Tokyo", label: "GMT+09:00", city: "Tokyo", offset: 9, x: 710, y: 121},
    %{id: "Australia/Adelaide", label: "GMT+09:30", city: "Adelaide", offset: 9.5, x: 724, y: 299},
    %{id: "Australia/Sydney", label: "GMT+10:00", city: "Sydney", offset: 10, x: 736, y: 285},
    %{id: "Pacific/Noumea", label: "GMT+11:00", city: "Noumea", offset: 11, x: 760, y: 277},
    %{id: "Pacific/Auckland", label: "GMT+12:00", city: "Auckland", offset: 12, x: 780, y: 295},
    %{id: "Pacific/Tongatapu", label: "GMT+13:00", city: "Nuku'alofa", offset: 13, x: 790, y: 258}
  ]

  def all, do: @timezones

  def get(id) do
    Enum.find(@timezones, fn tz -> tz.id == id end)
  end

  def label_for(id) do
    case get(id) do
      nil -> id
      tz -> "#{tz.label} — #{tz.city}"
    end
  end

  def grouped_options do
    @timezones
    |> Enum.map(fn tz -> {"#{tz.label} — #{tz.city}", tz.id} end)
  end
end
