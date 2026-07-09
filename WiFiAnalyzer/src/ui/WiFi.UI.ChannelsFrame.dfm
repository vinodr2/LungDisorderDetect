object frameChannels: TframeChannels
  Left = 0
  Top = 0
  Width = 900
  Height = 480
  TabOrder = 0
  object pnlHeader: TPanel
    Left = 0
    Top = 0
    Width = 900
    Height = 36
    Align = alTop
    BevelOuter = bvNone
    ShowCaption = False
    TabOrder = 0
    object lblBand: TLabel
      Left = 12
      Top = 11
      Width = 31
      Height = 15
      Caption = 'Band:'
    end
    object lblRec: TLabel
      Left = 320
      Top = 11
      Width = 130
      Height = 15
      Caption = 'Recommended channel: -'
    end
    object cboBand: TComboBox
      Left = 49
      Top = 7
      Width = 100
      Height = 23
      Style = csDropDownList
      ItemIndex = 0
      TabOrder = 0
      Text = '2.4 GHz'
      OnChange = cboBandChange
      Items.Strings = (
        '2.4 GHz'
        '5 GHz'
        '6 GHz')
    end
    object chkFill: TCheckBox
      Left = 165
      Top = 10
      Width = 130
      Height = 17
      Caption = 'Fill arcs'
      TabOrder = 1
      OnClick = chkFillClick
    end
  end
  object pbSpectrum: TPaintBox
    Left = 0
    Top = 36
    Width = 900
    Height = 444
    Align = alClient
    OnPaint = pbSpectrumPaint
    ExplicitLeft = 0
    ExplicitTop = 36
  end
end
