import Toybox.Graphics;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Ticket 12 probe: can the packed database ride in base64 string resources,
// decode to a ByteArray on the watch, and be read field by field?
class DataProbeView extends WatchUi.View {
    const ENTRY_SIZE = 22;

    var _bytes as ByteArray?;
    var _secOff as Array<Number> = [];
    var _secLen as Array<Number> = [];
    var _timer as Timer.Timer?;
    var _done as Boolean = false;

    function initialize() { View.initialize(); }

    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 200, true);
    }
    function onHide() as Void { if (_timer != null) { _timer.stop(); } }

    function u16(off as Number) as Number {
        return _bytes.decodeNumber(Lang.NUMBER_FORMAT_UINT16,
            { :offset => off, :endianness => Lang.ENDIAN_LITTLE });
    }
    function u32(off as Number) as Number {
        return _bytes.decodeNumber(Lang.NUMBER_FORMAT_UINT32,
            { :offset => off, :endianness => Lang.ENDIAN_LITTLE }).toNumber();
    }
    function s16(off as Number) as Number {
        return _bytes.decodeNumber(Lang.NUMBER_FORMAT_SINT16,
            { :offset => off, :endianness => Lang.ENDIAN_LITTLE });
    }

    function load() as Void {
        var t0 = System.getTimer();
        var s = (WatchUi.loadResource(Rez.Strings.Data0) as String) +
                (WatchUi.loadResource(Rez.Strings.Data1) as String);
        var t1 = System.getTimer();
        System.println("chars=" + s.length() + " loadMs=" + (t1 - t0));

        _bytes = StringUtil.convertEncodedString(s, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
        var t2 = System.getTimer();
        System.println("bytes=" + _bytes.size() + " decodeMs=" + (t2 - t1));

        var n = u16(0);
        for (var i = 0; i < n; i += 1) {
            _secOff.add(u32(2 + i * 8));
            _secLen.add(u32(6 + i * 8));
        }
        System.println("sections=" + n);
        for (var i = 0; i < n; i += 1) {
            System.println("  section " + i + " off=" + _secOff[i] + " len=" + _secLen[i]);
        }
        var st = System.getSystemStats();
        System.println("mem after load " + st.usedMemory + "/" + st.totalMemory);
    }

    function name(idx as Number) as String {
        var base = _secOff[1];
        var count = u16(base);
        var offs = base + 2;
        var blob = offs + (count + 1) * 2;
        var a = u16(offs + idx * 2);
        var b = u16(offs + (idx + 1) * 2);
        var chars = _bytes.slice(blob + a, blob + b);
        return StringUtil.convertEncodedString(chars, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
        }) as String;
    }

    function dump(idx as Number) as Void {
        var o = _secOff[0] + idx * ENTRY_SIZE;
        System.println("#" + idx + " " + name(idx) +
            " number=" + u16(o) +
            " order=" + u16(o + 2) +
            " stage=" + _bytes[o + 4] +
            " spirit=" + _bytes[o + 5] +
            " element=" + _bytes[o + 6] +
            " baseLevel=" + _bytes[o + 7] +
            " flags=" + _bytes[o + 8] +
            " ability=" + _bytes[o + 9] +
            " evo=" + s16(o + 10) +
            " HP=" + u16(o + 12) +
            " EN=" + u16(o + 14) +
            " CR=" + u16(o + 16) +
            " AB=" + u16(o + 18) +
            " rarity=" + _bytes[o + 20] +
            " exclusive=" + _bytes[o + 21]);
    }

    function tick() as Void {
        if (_done) { return; }
        _done = true;
        load();
        for (var i = 0; i < 593; i += 1) { dump(i); }

        // walk every record, the way the Database app browsing 593 entries would
        var t0 = System.getTimer();
        var sum = 0;
        for (var i = 0; i < 593; i += 1) {
            sum += u16(_secOff[0] + i * ENTRY_SIZE + 12);
        }
        var t1 = System.getTimer();
        System.println("walked 593 HP fields in " + (t1 - t0) + "ms sum=" + sum);

        var t2 = System.getTimer();
        var acc = 0;
        for (var i = 0; i < 593; i += 1) { acc += name(i).length(); }
        var t3 = System.getTimer();
        System.println("read 593 names in " + (t3 - t2) + "ms totalChars=" + acc);

        var st = System.getSystemStats();
        System.println("mem final " + st.usedMemory + "/" + st.totalMemory);
        System.println("DONE");
        _timer.stop();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }
}
