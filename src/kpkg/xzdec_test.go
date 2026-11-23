package main

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"io"
	"strings"
	"testing"
	"testing/iotest"
)

var xzFixtures = []struct{ name, plain, data string }{
	{"crc32", "p", "/Td6WFoAAAFpIt42AgAhARYAAAB0L+Wj4AXbAeNdADCCiHT1RnFG6A8CBHlO0108RmzTjdKKwM1gNqQ9rz1r2P4KulSxNj2r25VK0zMi8QXWAWPUHFYBBq15MteW7gwnx80lXeIq9GYlnDrL5CzTzpILzx5moo/NJWGxVI9iAy7ZpveZcP0Vw63718qlvlWml1Xn5eKwmsNLbsq+8Co/2why+eLmK97Ie8neSAtRFgdwCIX15wOE1/OThXze5J6kEsQ9G0zM9qdWjBLlpiRov/wc+OADXP4qG6wFM5JdCrMpsCi2/7Hv/H4/Ql1URfRTybm0KU2JAhueIR7kBByPMF33R18YUZBs/qHNgjno/f6XEBNNMcS4MVvNwwToieWi+2YKmpp1SzXHZqIQvxS5vKrnKTh/A2n9zglpOIGoAkEcLePea76dEddmGOxwI64kVzhs+AjX3OsubeWfDL/NeoaM12WBY/O+/+OowMX7ShE1X5QyT9AToS80v8jbZ53FdiopqH5lkQh+XuTz8udakYCDOR7GK9T/meptqmZSxKNwkFT1bpBPU8jIPiOqDBY6Y7cZTzY99bZvYlsj60MLOobMTxxVWy90w8zVbjOOMFDxUm95xV4kh8bsHCKy/7Qdegquk11Xz70UKNp5hmXQMnt5ZZHuucDH/OL1Ek60yO4cKAAAro/8lQAB+wPcCwAAF653mz4wDYsCAAAAAAFZWg=="},
	{"crc64", "p", "/Td6WFoAAATm1rRGAgAhARwAAAAQz1jM4AXbAeNdADCCiHT1RnFG6A8CBHlO0108RmzTjdKKwM1gNqQ9rz1r2P4KulSxNj2r25VK0zMi8QXWAWPUHFYBBq15MteW7gwnx80lXeIq9GYlnDrL5CzTzpILzx5moo/NJWGxVI9iAy7ZpveZcP0Vw63718qlvlWml1Xn5eKwmsNLbsq+8Co/2why+eLmK97Ie8neSAtRFgdwCIX15wOE1/OThXze5J6kEsQ9G0zM9qdWjBLlpiRov/wc+OADXP4qG6wFM5JdCrMpsCi2/7Hv/H4/Ql1URfRTybm0KU2JAhueIR7kBByPMF33R18YUZBs/qHNgjno/f6XEBNNMcS4MVvNwwToieWi+2YKmpp1SzXHZqIQvxS5vKrnKTh/A2n9zglpOIGoAkEcLePea76dEddmGOxwI64kVzhs+AjX3OsubeWfDL/NeoaM12WBY/O+/+OowMX7ShE1X5QyT9AToS80v8jbZ53FdiopqH5lkQh+XuTz8udakYCDOR7GK9T/meptqmZSxKNwkFT1bpBPU8jIPiOqDBY6Y7cZTzY99bZvYlsj60MLOobMTxxVWy90w8zVbjOOMFDxUm95xV4kh8bsHCKy/7Qdegquk11Xz70UKNp5hmXQMnt5ZZHuucDH/OL1Ek60yO4cKAAArlzO9dWL2BkAAf8D3AsAAAHs5gCxxGf7AgAAAAAEWVo="},
	{"sha256", "p", "/Td6WFoAAArh+wyhAgAhAQwAAACPmEGc4AXbAgNdADCCiHT1RnFG6A8CBHlO0108RmzTjdKKwM1gNqQ9rz1r2P4KulSxNj2r2arNohmoYdmt4lD0oDnMANlCJdjqlrNqmqO96FVtZNmbDbmkg1Ob6xQs9KzJIdlQ1qmM7EGldtVHS61aP8VuYUo5zlFR4r5+6v7JL+mjFXY4H1x8b0R4qwZEcyvy2b51hD1q/cn/ituQw3TSY+44fu7EfpNc9ZOMIR0Ghpb9rZCPdKrtZria+Xtc6agXVF9YNfTvAo0r5ozVdgE0i1UA9ifvoSce0Eo4RHpCwL4ZNpCNO+pIAf4Vpugz7vlxsaJhVFisFMe8WATuuIVsWVQ/600RTKedbwW2sUQUYGOoBqD8vEARXuVky2Uw5P6i5uHhdldNlJfkF5cd9MLFPNkeQUk27ivZimdB7/IoXUTx7UwUn6tjqah12qC7XqcSc+eWVes2T4DnWs2R51UmYIy+xwmaHsLAAOoeJbogB5IdI9ZwrAiL7HhqYfqFgstJSKLAvqjKu1ms4YPXMqsG6h2VCjZwRXKAgvyArSPqB80JoA4LEqycMAUmWzbarXe747ThbFhrOiLEM9IkUVw4t8S3wQl2yBm/Xye5QO4p6cRwx7Fe/D3GSxGYYmbOaRTY1LjdzsmznoUz9RkOkfOCvMAdVMHVy2NCSwIDlQW9k3w2PAEQtNIqjFttQaUAAABbAa9ipG43CCRkGmY69ZBWW3/ttdLtPIC+jum5p3MYiwABtwTcCwAAELjNUbbp3xwCAAAAAApZWg=="},
	{"none", "p", "/Td6WFoAAAD/EtlBAgAhARYAAAB0L+Wj4AXbAeNdADCCiHT1RnFG6A8CBHlO0108RmzTjdKKwM1gNqQ9rz1r2P4KulSxNj2r25VK0zMi8QXWAWPUHFYBBq15MteW7gwnx80lXeIq9GYlnDrL5CzTzpILzx5moo/NJWGxVI9iAy7ZpveZcP0Vw63718qlvlWml1Xn5eKwmsNLbsq+8Co/2why+eLmK97Ie8neSAtRFgdwCIX15wOE1/OThXze5J6kEsQ9G0zM9qdWjBLlpiRov/wc+OADXP4qG6wFM5JdCrMpsCi2/7Hv/H4/Ql1URfRTybm0KU2JAhueIR7kBByPMF33R18YUZBs/qHNgjno/f6XEBNNMcS4MVvNwwToieWi+2YKmpp1SzXHZqIQvxS5vKrnKTh/A2n9zglpOIGoAkEcLePea76dEddmGOxwI64kVzhs+AjX3OsubeWfDL/NeoaM12WBY/O+/+OowMX7ShE1X5QyT9AToS80v8jbZ53FdiopqH5lkQh+XuTz8udakYCDOR7GK9T/meptqmZSxKNwkFT1bpBPU8jIPiOqDBY6Y7cZTzY99bZvYlsj60MLOobMTxxVWy90w8zVbjOOMFDxUm95xV4kh8bsHCKy/7Qdegquk11Xz70UKNp5hmXQMnt5ZZHuucDH/OL1Ek60yO4cKAAAAAH3A9wLAABsbrXsqAAK/AIAAAAAAFla"},
	{"lp", "p", "/Td6WFoAAAFpIt42AgAhARYAAAB0L+Wj4AXbAdwcADCCnXF8hmY4zqFOoLI74ltdo+u4DJ4hi0TD0v7AoWqlDZUsZPWA+K4IiEY0qzsnJf/Mo3V7wVms70BH3Vh82C5Y2jGcKCpTlYHRmOF6qxPlcZqrMpZ6ypP77vXe9+Cd1/US3+6ExtOagOGNFjPn3bwmLLR7vnxgZNBw7s3dpAhzrusW5unrIks9gfSoACSSLAXsbcTeQ/AJCFCHVTso7MBHTurWh+YptoNdlX6Y5AIA9+WTLxIQs6SZY4KwHlSgoNpOEHnriHw6QcXjyrY2LkfhwqTpgPUE0063J9xnEE7DMB/ENNU3DasovmoU8BLFNDsf7yWrR1DL1jASg+vO3opG2Ixz6+ewYoSOctossW2b27lLFTUWvz5iCiRLtxBVwlcKZDt/Up8Asb59DkERTAoTx3jmO2k55JYkP/E2kN+03GZIOvtpi1UBOsjWLPYYtMd787OpH7cYcvKwJyWWUmq7sQAqblItd0vNgV9Sl9+B2D2nher6Bgna6ush4jpcS6qSAz7XgcQQYNSVDHlgVkycG1mJpG/8T7D589XmmzzdnCAi8sFjCnKKm1KNY2yG6WgjGJy5D6mbTXGyj7a1u38hmAuggYl9bqU7BupUvRGbNFcAKs1+6h8K65YHAK6P/JUAAfQD3AsAAMIcIWo+MA2LAgAAAAABWVo="},
	{"blocks", "p", "/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4AHzANxdADCCiHT1RnFG6A8CBHlO0108RmzTjdKKwM1gNqQ9rz1r2P4KulSxNj2r25VK0zMi8QXWAWPUHFYBBq15MteW7gwnx80lXeIq9GYlnDrL5CzTzpILzx5moo/NJWGxVI9iAy7ZpveZcP0Vw63718qlvlWml1Xn5eKwmsNLbsq+8Co/2why+eLmK97Ie8neSAtRFgdwCIX15wOE1/OThXze5J6kEsQ9G0zM9qdWjBLlpiRov/wc+OADXP4qG6wFM5JdCrMpsCi2/7Hv/H4/Ql1URfRTybm0KU2GdW6D0gAA5gA3v6tDayUCACEBFgAAAHQv5aPgAfMA5V0ANJ2IyRTSy1ZTVpil3zj/mRvP+fwbmhSNdZY+970c2KKeIod3pMhF+XUCbJk4sWob97VqjNt/Zjd26YxhDfJJXiAreG0nfr/yTqlZ1KpcYXW/IXkMkwbPinvptYgOaukuEek/TGXKXCxT6Bv1AjWdU1UzTyyz5cako7tuHqTmY0E4/pIkgy+/NKMC22MrLTXqehHKW1PDMg0e4Pe6n6+6SpJcGmTqlgaOjJqhvx0rQSN83eOVTtnTtvoYiDWdmgn6NfPmH4t1NGOThrHiQyHd44qhzUHfP6vq6SxZgTX2SUF0+ENhIAAAAAA7eDgzaDqasAIAIQEWAAAAdC/lo+AB8wDpXQA0mMmxa3lwn5OlSZ1l2OHAHGDQZoXZ4FcpHNmbxMQe+iS572PajHVs5DHA/meevT4gCqYMGB3txCmcUB9AHg67UgfvwK+cxrUmgd4x+Lb0LRRQkwyzfjrAwLn4vcpba8+Z7OyY1kIbkNLbMNh9cU3f/Xr3l3wqZ00Oumr1Zww4Waf8JeQ/4Ac/6aEVCyl14oPUWUVF5AJS88mZYRPBf/XqsZMWJdZDHKiKLjcemVFe8I1UcJyMf1SLBUlRmAUieSoTx7o/f+KYPd2j5KP0bStw4IyOVO+HJ5jLDH57Msyx7MzsfLByI6nGAAAAAAAlZTG9V69OVgAD+AH0A4EC9AOFAvQDAABkqnv2rCc+LQQAAAAABFla"},
	{"stored", "r", "/Td6WFoAAAFpIt42AgAhARYAAAB0L+WjAQGPRkKbVV2lBFbeRLeIUh2cqN7R8W/xQ8BYogFRjaA/hGG9aFT6aYzsEb4o/urfE2XiyJItSOTUhVH4X0lbNyga1ZpxOoHMipPeMyq39gL0reNSUd6wns15hzuEHkGZYqvGXjxy1sD5QDWaZu48I2RvVlSClPdQOez2Yl2GcWeCep+7UHgs8xbLFAIZggubarrp3Dw2sKMIwx4V+wzfNYHg0ZfXHPaFBKP9MKcpfLpyr08rPPyysg51ArSTDUGNvUrQDp9/7wzJyfWcl2powUmGPrbgcxgMBQ0pT369Fen1OBZuGRsSklDTh3CUoWznJYlyJC19QbWIK6CtOCCavFFAHjpbuKGUZ+q+jmv/61ebF6dVy0/QJBcD9UhhEdVoWQppKh94IQPAzS6KEIcLLqijolcEcaxEF1w8TsA/jUf7UX0pws1bRPHM66qaE7aAqrMnccrCAHbQkg2gPCtOpYfo4FRHfV0ydc2P60RNmlJm4gMasHE7i2+Vg9TjLGnCs7Mg/1SldhqqSzf9bLcooAHfBAC6UhiFAAGkA5ADAAAIon65PjANiwIAAAAAAVla"},
	{"concat", "p", "/Td6WFoAAAFpIt42AgAhARYAAAB0L+Wj4AJXAPldADCCiHT1RnFG6A8CBHlO0108RmzTjdKKwM1gNqQ9rz1r2P4KulSxNj2r25VK0zMi8QXWAWPUHFYBBq15MteW7gwnx80lXeIq9GYlnDrL5CzTzpILzx5moo/NJWGxVI9iAy7ZpveZcP0Vw63718qlvlWml1Xn5eKwmsNLbsq+8Co/2why+eLmK97Ie8neSAtRFgdwCIX15wOE1/OThXze5J6kEsQ9G0zM9qdWjBLlpiRov/wc+OADXP4qG6wFM5JdCrMpsCi2/7Hv/H4/Ql1URfRTybm0KU2JAhueIR7kBByPMF33R18YUZBs/qHNgjno/f6XEBI16M6FJAAAAACE6azuAAGRAtgEAADxe0aLPjANiwIAAAAAAVlaAAAAAAAAAAD9N3pYWgAAAP8S2UECACEBFgAAAHQv5aPgA4MBUF0AORjJTwtLUpxUOEPK4YcQhhG9iS+gQGny/ciB6t0xgI50CQilS1j9yi43YYi/ZUGUiY1cfwVqQSfqVpUqXBaB74eGRgK5slGDUvsKPpXFMuHGPAFCFshmPTktbeY3bbNqvSQGMYP73/t4GMuGq1lahTzFBtfiEtIWHq03hQpCDVEPvzC6/lSdpIn03qzsX/4WAcrwgcAgcGTWo7vkdVn7JLXRZnAYCw6K5FQqz8vU/7OIq4C91swcJIaTWgtM8tuVVXMQbiNc/gLAK1JwBHsKLUqg93DpIja5uuG40dK8OUf4aIelqSU4E3aU1GRuZdW73lFqEsGlUJQC/hdsXISJXw/Zu46jZhjKD9FJ6ZvfKv9PkPFUx8fsV479vcR54E+qcs6ZwUwGKyAEquulTTn10u5twlQbBM8e3oPdn9Rk8DibPcrC9j2AUvHa3DKxqWN6AAAB5AKEBwAAwOk0U6gACvwCAAAAAABZWgAAAAA="},
	{"slide", "s", "/Td6WFoAAAFpIt42AgAhAQAAAAA3J5fW//76AlBdAAAAUlAKhPmbsoAhqWnWJ+A+BlpfBI1T1AS6OVcFCcFVJN6duHFZMWChn/lvSXPyyOqMuhqLKWkhgP4zg2avRm3snomKC4PwPA6Jjj/tX+eekNkc/zL0suA5UbLSFBW0xXG62wbjeZqfuzjBsACskwuqBhkDEggVW5vISPAyLv4toIfI8KTg0lHrjWdWkrJNhMXxhjHfamJbwnkt2fc8c7p0dAfYPKlWIiShZvhahF8wZ9L2S0kufyDr2/gQDpR4d8c/a++0zZXib/ZEbgbPC4Iay9t68FeNmP+QwD7mwRJBde4DnqjoegSV0b7AfmdyeuC6vVn/y92z0tPsI/kLnjc9v9WDUooG7UH9E/uFAI3/OoAmgINRrCtuqCs0rls56r+GInwsRPW90T/wbBnCDL8VCpLvZ6qgzF/vVTGifNVd64ZCEz1noET4Ny1g3etysuRG9lTwiHUsMNvCUFSRIpcGA1/JcDsUwDI3mKUVAaXoowkq7Kr/WiascgwWkqe+OY8k4XCepyNf7CjLhdGVmIp+KpHyJ3X3GcAGmE2Y/div1ZAPxCVT+PWRNjEFpbDub8FwTUcM0ZERqq1gHbrOsScYXFmG6WZSWL7pdqxZ5OVbBQj5x9qt/PtSK3TNHlsgQvndUz34KWQJO4DLKmzftTvwxL0uX6oPPktmQpATDv8Qk/hxeFn4C83/lShGD6n8fN77mjAuVsCPhfODgcBlxCVT+PWRNjEFpbDub8FwTUcM0ZERqq1gHbrOsScYXFmG6WZSWL7pdqxZ5OVbBOaE6rif/xABKwDsc1On/b6ufDEan7eNMW5wnqcjX+woy4XRlZiKfiqR8id19xnABphNmP3Yr9WQD8QlU/j1kTYxBaWw7m/BcE1HDNGREaqtYB26zrEnGFxZhulmUli+6XasWeTlWwUI+cfarfz7Uit0zR5bIEL53VM9+ClkCTuAyyps37U78MS9Ll+qDz5LZkKQEw7/EJP4cXhZ+AvN/5UoRg+p/Hze+5owLlbAj4Xzg4HAZcQlU/j1kTYxBaWw7m/BcE1HDNGREaqtYB26zrEnGFxZhulmUli+6XasWeTlWwUI+cfarfz7Uit0zR5bIEL53VM9+ClkCTuAyyps37U78MS9Ll+qDz5LZkKQEw7/EJP4cXhZ+AvN/5UoRg+p/Hze+5owLlbAj4Xzg4HAZcQlUQ8/spAB8wCZAOxzU6f9vq58MRqft40xbnCepyNf7CjLhdGVmIp+KpHyJ3X3GcAGmE2Y/div1ZAPxCVT+PWRNjEFpbDub8FwTUcM0ZERqq1gHbrOsScYXFmG6WZSWL7pdqxZ5OVbBQj5x9qt/PtSK3TNHlsgQvndUz34KWQJO4DLKmzftTvwxL0uX6oPPktmQpATDv8Qk/hxeFn4C8zvuPUAAACs/IvIAAG4CICAwALdFSQsPjANiwIAAAAAAVla"},
	{"empty", "", "/Td6WFoAAATm1rRGAAAAABzfRCEftvN9AQAAAAAEWVo="},
	{"bcj", "", "/Td6WFoAAATm1rRGAgEEACEBFgANhjUf4AA/ADhdADCCiHT1RnFG6A8CBHlO0108RmzTjdKKwM1gNqQ9rz1r2P4KulSxNj2r25VK0zMi8QXWAWPSuQGPADJJk+jZhXytAAFUQOtsjYgftvN9AQAAAAAEWVo="},
	{"delta", "", "/Td6WFoAAATm1rRGAgEDAQAhARZ5IMTuAQA/YalYEP0I97JU9P2lYvUZ/5FcCQmSWxHvDQenVPT9u0YJCahPB+8NmGr0/btGCQmoSwX7/KNt8QED+aVaC/i5UQAySZPo2YV8rQABWEDnIzgkH7bzfQEAAAAABFla"},
}

func xzTestText(n int) []byte {
	w := strings.Fields("the quick brown fox jumps over a lazy dog while kpkg unpacks data.tar.xz from every deb in the archive")
	var b []byte
	x := uint32(7)
	for len(b) < n {
		x = x*1103515245 + 12345
		b = append(b, w[x>>16%uint32(len(w))]...)
		b = append(b, " \n"[x>>12&1])
	}
	return b[:n]
}

func xzTestRand(n int) []byte {
	b := make([]byte, n)
	x := uint32(99)
	for i := range b {
		x = x*1664525 + 1013904223
		b[i] = byte(x >> 24)
	}
	return b
}

func xzTestPat(n int) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = byte(i % 251)
	}
	return b
}

func xzPlain(k string) []byte {
	switch k {
	case "p":
		return xzTestText(1500)
	case "r":
		return xzTestRand(400)
	case "s":
		return xzTestPat(5 << 20)
	}
	return []byte{}
}

func xzFixture(t testing.TB, name string) []byte {
	for _, f := range xzFixtures {
		if f.name == name {
			b, err := base64.StdEncoding.DecodeString(f.data)
			if err != nil {
				t.Fatal(err)
			}
			return b
		}
	}
	t.Fatal("no fixture " + name)
	return nil
}

func xzDecode(in io.Reader) ([]byte, error) {
	r, err := newXZReader(in)
	if err != nil {
		return nil, err
	}
	var b bytes.Buffer
	_, err = io.CopyN(&b, r, 64<<20)
	if err == io.EOF {
		err = nil
	} else if err == nil {
		err = errors.New("output too large")
	}
	return b.Bytes(), err
}

func TestXZFixtures(t *testing.T) {
	for _, f := range xzFixtures {
		if f.name == "bcj" || f.name == "delta" {
			continue
		}
		in := xzFixture(t, f.name)
		want := xzPlain(f.plain)
		got, err := xzDecode(bytes.NewReader(in))
		if err != nil || !bytes.Equal(got, want) {
			t.Errorf("%s: err=%v len=%d want %d", f.name, err, len(got), len(want))
		}
		if f.name == "slide" {
			continue
		}
		r, err := newXZReader(iotest.OneByteReader(bytes.NewReader(in)))
		if err != nil {
			t.Fatalf("%s: %v", f.name, err)
		}
		got, err = io.ReadAll(iotest.OneByteReader(r))
		if err != nil || !bytes.Equal(got, want) {
			t.Errorf("%s one byte: err=%v", f.name, err)
		}
		if n, err := r.Read(make([]byte, 8)); n != 0 || err != io.EOF {
			t.Errorf("%s: read after end = %d, %v", f.name, n, err)
		}
	}
}

func TestXZFilters(t *testing.T) {
	for _, c := range []struct{ name, id string }{{"bcj", "0x4"}, {"delta", "0x3"}} {
		_, err := xzDecode(bytes.NewReader(xzFixture(t, c.name)))
		if err == nil || !strings.Contains(err.Error(), "unsupported filter "+c.id) {
			t.Errorf("%s: %v", c.name, err)
		}
	}
}

func xzWrap(dict byte, chunks, plain []byte) []byte {
	le := binary.LittleEndian
	b := []byte{0xfd, '7', 'z', 'X', 'Z', 0, 0, 1}
	b = le.AppendUint32(b, crc32.ChecksumIEEE(b[6:8]))
	h := []byte{2, 0, 0x21, 1, dict, 0, 0, 0}
	h = le.AppendUint32(h, crc32.ChecksumIEEE(h))
	b = append(append(b, h...), chunks...)
	for len(b)%4 != 0 {
		b = append(b, 0)
	}
	b = le.AppendUint32(b, crc32.ChecksumIEEE(plain))
	idx := binary.AppendUvarint([]byte{0, 1}, uint64(len(h)+len(chunks)+4))
	idx = binary.AppendUvarint(idx, uint64(len(plain)))
	for len(idx)%4 != 0 {
		idx = append(idx, 0)
	}
	idx = le.AppendUint32(idx, crc32.ChecksumIEEE(idx))
	f := append(le.AppendUint32(nil, uint32(len(idx)/4-1)), 0, 1)
	b = le.AppendUint32(append(b, idx...), crc32.ChecksumIEEE(f))
	return append(append(b, f...), 'Y', 'Z')
}

func TestXZChunks(t *testing.T) {
	src := xzFixture(t, "crc32")
	c := src[12+(int(src[12])+1)*4:]
	cs := int(c[3])<<8 | int(c[4]) + 1
	if c[0] != 0xe0 || c[6+cs] != 0 {
		t.Fatalf("unexpected fixture layout %x", c[:8])
	}
	lz := append([]byte{}, c[:6+cs]...)
	lz[0] = 0xc0 | lz[0]&0x1f
	text := xzTestText(1500)
	stored := append([]byte{1, 0, 15}, make([]byte, 16)...)
	tail := []byte{2, 0, 4, 't', 'a', 'i', 'l', '!'}
	plain := append(append(make([]byte, 16), text...), "tail!"...)
	ok := append(append(append(append([]byte{}, stored...), lz...), tail...), 0)
	got, err := xzDecode(bytes.NewReader(xzWrap(0x16, ok, plain)))
	if err != nil || !bytes.Equal(got, plain) {
		t.Fatalf("mixed chunks: %v", err)
	}
	lz80 := append([]byte{}, lz...)
	lz80[0] = 0x80 | lz[0]&0x1f
	for i, ch := range [][]byte{
		append(append([]byte{}, tail...), 0),
		append(append(append([]byte{}, stored...), lz80[:5]...), append(lz80[6:], 0)...),
		append(append([]byte{}, stored...), 3, 0),
		append(append([]byte{}, lz[:5]...), 0xe1),
	} {
		if _, err := xzDecode(bytes.NewReader(xzWrap(0x16, ch, plain))); err == nil {
			t.Errorf("bad chunk sequence %d decoded", i)
		}
	}
	if _, err := xzDecode(bytes.NewReader(xzWrap(38, ok, plain))); err == nil || !strings.Contains(err.Error(), "dictionary") {
		t.Errorf("huge dictionary: %v", err)
	}
}

func TestXZTruncated(t *testing.T) {
	for _, name := range []string{"crc32", "crc64", "sha256", "none", "lp", "blocks", "stored", "empty"} {
		in := xzFixture(t, name)
		for n := range len(in) {
			if _, err := xzDecode(bytes.NewReader(in[:n])); err == nil {
				t.Errorf("%s truncated to %d: no error", name, n)
			}
		}
	}
	in := xzFixture(t, "concat")
	if _, err := xzDecode(bytes.NewReader(in[:len(in)-2])); err == nil {
		t.Error("partial stream padding accepted")
	}
}

func TestXZCorrupt(t *testing.T) {
	for _, name := range []string{"crc32", "crc64", "sha256", "lp", "blocks", "stored", "empty", "none", "concat"} {
		in := xzFixture(t, name)
		for i := range in {
			for _, x := range []byte{1, 0x80} {
				b := append([]byte{}, in...)
				b[i] ^= x
				_, err := xzDecode(bytes.NewReader(b))
				if err == nil && name != "none" && name != "concat" {
					t.Errorf("%s: flip %#x at %d: no error", name, x, i)
				}
			}
		}
	}
	for _, b := range [][]byte{nil, []byte("plain text, not xz"), append(xzFixture(t, "crc32"), "junk"...)} {
		if _, err := xzDecode(bytes.NewReader(b)); err == nil {
			t.Errorf("accepted %q", b)
		}
	}
}

func FuzzXZ(f *testing.F) {
	for _, x := range xzFixtures {
		if x.name != "slide" {
			f.Add(xzFixture(f, x.name))
		}
	}
	f.Fuzz(func(t *testing.T, b []byte) {
		xzDecode(bytes.NewReader(b))
	})
}

func FuzzXZChunks(f *testing.F) {
	for _, n := range []string{"crc32", "lp", "stored"} {
		b := xzFixture(f, n)
		f.Add(b[12+(int(b[12])+1)*4:])
	}
	f.Fuzz(func(t *testing.T, b []byte) {
		xzDecode(bytes.NewReader(xzWrap(0x16, b, nil)))
	})
}
