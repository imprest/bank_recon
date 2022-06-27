defmodule BankRecon do
  import Bitwise

  require Record
  Record.defrecordp(:wx, Record.extract(:wx, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxClose, Record.extract(:wxClose, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxSize, Record.extract(:wxSize, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxCommand, Record.extract(:wxCommand, from_lib: "wx/include/wx.hrl"))

  Record.defrecordp(
    :wxFileDirPicker,
    Record.extract(:wxFileDirPicker, from_lib: "wx/include/wx.hrl")
  )

  @behaviour :wx_object

  @title "Bank Reconciler"
  # @size {390, 660}
  @picker_file 1
  @btn_calc 2
  @label_interest 3
  @text_interest 4
  @text_result 5

  @wxHORIZONTAL :wx_const.wxHORIZONTAL()
  @wxVERTICAL :wx_const.wxVERTICAL()
  @wxEXPAND :wx_const.wxEXPAND()
  @wxALL :wx_const.wxALL()
  @wxRIGHT :wx_const.wxRIGHT()
  @wxLEFT :wx_const.wxLEFT()
  @wxTOP :wx_const.wxTOP()
  @wxBOTTOM :wx_const.wxBOTTOM()
  @wxDEFAULT :wx_const.wxDEFAULT()
  @wxTE_MULTILINE :wx_const.wxTE_MULTILINE()
  @wxALIGN_CENTER :wx_const.wxALIGN_CENTER()

  @moduledoc """
  Documentation for `BankRecon`.
  """

  @doc """
  Start BankRecon gui

  ## Examples

      iex> BankRecon.start_link()
      {:wx_ref, 35, :wxFrame, _pid}

  """
  def start_link() do
    :wx_object.start_link(__MODULE__, [], [])
  end

  def init(_args \\ []) do
    wx = :wx.new()
    frame = :wxFrame.new(wx, -1, @title)
    :wxFrame.center(frame)
    :wxFrame.connect(frame, :size)
    :wxFrame.connect(frame, :close_window)

    panel = :wxPanel.new(frame)

    main_sizer = :wxBoxSizer.new(@wxVERTICAL)
    top_sizer = :wxStaticBoxSizer.new(@wxVERTICAL, panel, label: "Select Bank CSV File:")

    file_picker = :wxFilePickerCtrl.new(panel, @picker_file)

    :wxSizer.add(top_sizer, file_picker, border: 5, flag: @wxALL ||| @wxEXPAND)
    :wxSizer.add(main_sizer, top_sizer, border: 10, flag: @wxALL ||| @wxEXPAND)

    :wxPanel.setSizer(panel, main_sizer)
    :wxSizer.fit(main_sizer, panel)

    :wxFrame.fit(frame)
    :wxFrame.show(frame)

    state = %{
      panel: panel
    }

    {frame, state}
  end

  def handle_event(wx(event: wxSize(size: size)), state = %{panel: panel}) do
    :wxPanel.setSize(panel, size)
    {:noreply, state}
  end

  def handle_event(wx(event: wxClose()), state), do: {:stop, :normal, state}
end
