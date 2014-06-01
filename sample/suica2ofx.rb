# -*- coding: utf-8 -*-
# $Id: suica.rb,v 1.7 2008-02-17 04:49:57 hito Exp $
require "pasori"
require 'rexml/document'

class Suica
  Type1 = {
    0x03 => '      精算機',
    0x05 => '    車載端末',
    0x07 => '      券売機',
    0x08 => '      券売機',
    0x09 => '      入金機',
    0x12 => '      券売機',
    0x14 => '    券売機等',
    0x15 => '    券売機等',
    0x16 => '      改札機',
    0x17 => '  簡易改札機',
    0x18 => '    窓口端末',
    0x19 => '    窓口端末',
    0x1A => '    改札端末',
    0x1B => '    携帯電話',
    0x1C => '  乗継精算機',
    0x1D => '  連絡改札機',
    0x1F => '  簡易入金機',
    0x23 => '新幹線改札機',
    0x46 => '  VIEW ALTTE',
    0x48 => '  VIEW ALTTE',
    0xC7 => '    物販端末',
    0xC8 => '      自販機',
  }

  Type2 = {
    0x01 => '              改札出場',
    0x02 => '              チャージ',
    0x03 => '            磁気券購入',
    0x04 => '                  精算',
    0x05 => '              入場精算',
    0x06 => '          改札窓口処理',
    0x07 => '              新規発行',
    0x08 => '              窓口控除',
    0x0d => '                  バス',
    0x0f => '                  バス',
    0x11 => '            再発行処理',
    0x13 => '      支払(新幹線利用)',
    0x14 => '  入場時オートチャージ',
    0x15 => '  出場時オートチャージ',
    0x1f => '          バスチャージ',
    0x23 => 'バス路面電車企画券購入',
    0x46 => '                  物販',
    0x48 => '          特典チャージ',
    0x49 => '              レジ入金',
    0x4a => '              物販取消',
    0x4b => '              入場物販',
    0xc6 => '          現金併用物販',
    0xcb => '      入場現金併用物販',
    0x84 => '              他社精算',
    0x85 => '          他社入場精算',
  }

  def initialize
    @pasori = Pasori.open
    @felica = @pasori.felica_polling(Felica::POLLING_SUICA)
  end

  def close
    @felica.close
    @pasori.close
  end

  def each(&block)
    @felica.foreach(Felica::SERVICE_SUICA_HISTORY) {|l|
      h = parse_history(l)
      yield(h)
    }
  end

  def check_val(hash, val)
    v = hash[val]
    if (v)
      v
    else
      sprintf("不明(%02x)", val)
    end
  end

  def read_in_out(&b)
    @felica.foreach(Felica::SERVICE_SUICA_IN_OUT) {|l|
      yield(l)
    }
  end

  def parse_history(l)
    d = l.unpack('CCnnCCCCvN')
    h = {}
    h["type1"] = check_val(Type1, d[0])
    h["type2"] = check_val(Type2, d[1])
    h["type3"] = d[2]
    y = (d[3] >> 9) + 2000
    m = (d[3] >> 5) & 0b1111
    dd = d[3] & 0b11111
    begin
      h["date"] = Time.local(y, m, dd)
    rescue
      return nil
    end
    h["from"] = sprintf("%02X-%02X", d[4], d[5])
    h["to"] = sprintf("%02X-%02X", d[6], d[7])
    h["balance"] = d[8]
    h["special"] = d[9]
    h
  end

  def dump_id()
    return hex_dump(@felica.idm)
  end
  def hex_dump(ary)
    ary.unpack("C*").map{|c| sprintf("%02X", c)}.join
  end
end

Type3 = {
  0x2000 => '出場',
  0x4000 => '出定',
  0xa000 => '入場',
  0xc000 => '入定',
  0x0040 => '清算',
}

suica = Suica.new

dtserver = Time.now.strftime("%Y%m%d000000[+9:JST]")
dtstart = nil
dtend = nil
suica.each {|h|
  if dtend == nil then
    dtend = h["date"].strftime("%Y%m%d000000[+9:JST]")
  end
  dtstart = h["date"].strftime("%Y%m%d000000[+9:JST]")
}

str = sprintf(<<EOS, dtserver, suica.dump_id, dtstart, dtend)
<?xml version="1.0" encoding="UTF-8"?>
<?OFX OFXHEADER="200" VERSION="200" SECURITY="NONE" OLDFILEUID="NONE" NEWFILEUID="NONE"?>
<!--
OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:UTF-8
CHARSET:CSUNICODE
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE
-->
<OFX>
  <SIGNONMSGSRSV1>
    <SONRS>
      <STATUS>
        <CODE>0</CODE>
        <SEVERITY>INFO</SEVERITY>
      </STATUS>
      <DTSERVER>%s</DTSERVER>
      <LANGUAGE>JPN</LANGUAGE>
      <FI>
        <ORG>EM</ORG>
      </FI>
    </SONRS>
  </SIGNONMSGSRSV1>
  <BANKMSGSRSV1>
    <STMTTRNRS>
      <TRNUID>0</TRNUID>
      <STATUS>
        <CODE>0</CODE>
        <SEVERITY>INFO</SEVERITY>
      </STATUS>
      <STMTRS>
        <CURDEF>JPY</CURDEF>
        <BANKACCTFROM>
          <BANKID>Suica</BANKID>
          <BRANCHID>0</BRANCHID>
          <ACCTID>%s</ACCTID>
          <ACCTTYPE>SAVINGS</ACCTTYPE>
        </BANKACCTFROM>
        <BANKTRANLIST>
          <DTSTART>%s</DTSTART>
          <DTEND>%s</DTEND>
EOS

i = 0
suica.each {|cur|
  if i != 0 then
    dtposted = @prev["date"].strftime("%Y%m%d000000[+9:JST]")
    trnamt = @prev["balance"] - cur["balance"]
    fitid = sprintf("%s%07d", @prev["date"].strftime("%Y%m%d"), @prev["special"]/256)
    name = @prev["type2"].strip
    str += sprintf(<<EOS, dtposted, trnamt, fitid, name)
          <STMTTRN>
            <TRNTYPE>INT</TRNTYPE>
            <DTPOSTED>%s</DTPOSTED>
            <TRNAMT>%d</TRNAMT>
            <FITID>%s</FITID>
            <NAME>%s</NAME>
          </STMTTRN>
EOS
  else
    @balamt = cur["balance"]
    @dtasof = cur["date"].strftime("%Y%m%d000000[+9:JST]")
  end
  i = i + 1
  @prev = cur
}

str += sprintf(<<EOS, @balamt, @dtasof)
        </BANKTRANLIST>
        <LEDGERBAL>
          <BALAMT>%d</BALAMT>
          <DTASOF>%s</DTASOF>
        </LEDGERBAL>
      </STMTRS>
    </STMTTRNRS>
  </BANKMSGSRSV1>
</OFX>
EOS

suica.close

print str 
