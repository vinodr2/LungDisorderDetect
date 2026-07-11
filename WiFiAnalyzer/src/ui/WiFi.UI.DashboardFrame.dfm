object frameDashboard: TframeDashboard
  Left = 0
  Top = 0
  Width = 900
  Height = 520
  TabOrder = 0
  object pbDash: TPaintBox
    Left = 0
    Top = 0
    Width = 900
    Height = 520
    Align = alClient
    OnPaint = pbDashPaint
    ExplicitLeft = 0
    ExplicitTop = 0
  end
  object tmrAnim: TTimer
    Enabled = False
    Interval = 33
    OnTimer = tmrAnimTimer
    Left = 820
    Top = 24
  end
end
