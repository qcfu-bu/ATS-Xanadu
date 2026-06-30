package main

import "xatsgo"

// keep the xatsgo import live even if main is trivial.
var _ = xatsgo.XATSNIL

func stmp_eqb_1657(goxtnm1 any, goxtnm2 any) bool {
	goxtnm3 := xatsgo.Xats_g_eq
	goxtnm4 := goxtnm3(goxtnm1, goxtnm2)
	return goxtnm4
}

func stmp_mem_1717(goxtnm5 *xatsgo.XatsCon, goxtnm6 any) bool {
	for {
		switch {
		case xatsgo.Xats_as_con(goxtnm5).Tag == 0:
			goxtnm7 := goxtnm5
			_ = goxtnm7
			return false
		case xatsgo.Xats_as_con(goxtnm5).Tag == 1:
			goxtnm8 := goxtnm5
			goxtnm9 := stmp_eqb_1657(goxtnm6, xatsgo.Xats_as_con(goxtnm8).Args[0])
			if goxtnm9 {
				return true
			} else {
				goxtnm5 = xatsgo.Xats_as_con(goxtnm8).Args[1].(*xatsgo.XatsCon)
				goxtnm6 = goxtnm6
				continue
			}
		default:
			panic("xats2go: XATS000_cfail")
		}
	}
}

func the_go_byref_get_2291() *xatsgo.XatsCon {
	goxtnm17 := xatsgo.Xats_a0ref_get
	goxtnm18 := goxtnm17(goxtnm16)
	switch {
	case xatsgo.Xats_as_con(goxtnm18).Tag == 0:
		goxtnm19 := goxtnm18
		_ = goxtnm19
		goxtnm20 := &xatsgo.XatsCon{Tag: 0, Args: []any{}}
		return goxtnm20
	case xatsgo.Xats_as_con(goxtnm18).Tag == 1:
		goxtnm21 := goxtnm18
		goxtnm22 := &xatsgo.XatsCon{Tag: 1, Args: []any{xatsgo.Xats_as_con(goxtnm21).Args[0], xatsgo.Xats_as_con(goxtnm21).Args[1].(*xatsgo.XatsCon)}}
		return goxtnm22
	default:
		panic("xats2go: XATS000_cfail")
	}
}

func byref_add_2781(goxtnm24 any) any {
	var goxtnm33 any
	{
		// I1Dvaldclist(LCSRCsome1(srcgen2/DATS/go1emit_byref0.dats)@(2528(line=103,offs=3)--2565(line=103,offs=40)))
		goxtnm25 := the_go_byref_get_2291()
		goxtnm26 := goxtnm25
		_ = goxtnm26
		goxtnm27 := stmp_mem_1717(goxtnm26, goxtnm24)
		var goxtnm32 any
		if goxtnm27 {
			goxtnm28 := struct{}{}
			goxtnm32 = goxtnm28
		} else {
			goxtnm29 := xatsgo.Xats_a0ref_set
			goxtnm30 := &xatsgo.XatsCon{Tag: 1, Args: []any{goxtnm24, goxtnm26}}
			goxtnm31 := goxtnm29(goxtnm16, goxtnm30)
			goxtnm32 = goxtnm31
		}
		goxtnm33 = goxtnm32
	}
	return goxtnm33
}

func byref_has_3018(goxtnm34 any) bool {
	{
		// I1Dvaldclist(LCSRCsome1(srcgen2/DATS/go1emit_byref0.dats)@(2829(line=117,offs=3)--2866(line=117,offs=40)))
		goxtnm35 := the_go_byref_get_2291()
		goxtnm36 := goxtnm35
		_ = goxtnm36
		goxtnm37 := stmp_mem_1717(goxtnm36, goxtnm34)
		return goxtnm37
	}
}

func byref_reset_3205() any {
	goxtnm39 := xatsgo.Xats_a0ref_set
	goxtnm40 := &xatsgo.XatsCon{Tag: 0, Args: []any{}}
	goxtnm41 := goxtnm39(goxtnm16, goxtnm40)
	return goxtnm41
}

func go_arm_set_3762() any {
	goxtnm45 := xatsgo.Xats_a0ref_set
	goxtnm46 := goxtnm45(goxtnm44, true)
	return goxtnm46
}

func go_arm_getq_3793() bool {
	goxtnm47 := xatsgo.Xats_a0ref_get
	goxtnm48 := goxtnm47(goxtnm44)
	return goxtnm48
}

func block_force_value_set_8475(goxtnm52 bool) any {
	goxtnm53 := xatsgo.Xats_a0ref_set
	goxtnm54 := goxtnm53(goxtnm51, goxtnm52)
	return goxtnm54
}

func block_force_value_get_8516() bool {
	goxtnm55 := xatsgo.Xats_a0ref_get
	goxtnm56 := goxtnm55(goxtnm51)
	return goxtnm56
}

func nient_memq_4413(goxtnm61 *xatsgo.XatsCon, goxtnm62 any) bool {
	var goxtnm70 bool
	switch {
	case xatsgo.Xats_as_con(goxtnm61).Tag == 0:
		goxtnm63 := goxtnm61
		_ = goxtnm63
		goxtnm70 = false
	case xatsgo.Xats_as_con(goxtnm61).Tag == 1:
		goxtnm64 := goxtnm61
		_ = xatsgo.Xats_gint_eq_sint_sint
		goxtnm66 := xatsgo.Xats_stamp_cmp(xatsgo.Xats_as_con(goxtnm64).Args[0].F0, goxtnm62)
		goxtnm67 := (goxtnm66 == 0)
		var goxtnm69 bool
		if goxtnm67 {
			goxtnm69 = true
		} else {
			goxtnm68 := nient_memq_4413(xatsgo.Xats_as_con(goxtnm64).Args[1].(*xatsgo.XatsCon), goxtnm62)
			goxtnm69 = goxtnm68
		}
		goxtnm70 = goxtnm69
	default:
		panic("xats2go: XATS000_cfail")
	}
	return goxtnm70
}

func nient_find_4609(goxtnm71 *xatsgo.XatsCon, goxtnm72 any) any {
	var goxtnm80 string
	switch {
	case xatsgo.Xats_as_con(goxtnm71).Tag == 0:
		goxtnm73 := goxtnm71
		_ = goxtnm73
		goxtnm80 = xatsgo.XATSSTRN("")
	case xatsgo.Xats_as_con(goxtnm71).Tag == 1:
		goxtnm74 := goxtnm71
		_ = xatsgo.Xats_gint_eq_sint_sint
		goxtnm76 := xatsgo.Xats_stamp_cmp(xatsgo.Xats_as_con(goxtnm74).Args[0].F0, goxtnm72)
		goxtnm77 := (goxtnm76 == 0)
		var goxtnm79 any
		if goxtnm77 {
			goxtnm79 = xatsgo.Xats_as_con(goxtnm74).Args[0].F1
		} else {
			goxtnm78 := nient_find_4609(xatsgo.Xats_as_con(goxtnm74).Args[1].(*xatsgo.XatsCon), goxtnm72)
			goxtnm79 = goxtnm78
		}
		goxtnm80 = goxtnm79
	default:
		panic("xats2go: XATS000_cfail")
	}
	return goxtnm80
}

func nullary_inst_add_4470(goxtnm81 any, goxtnm82 string) any {
	var goxtnm93 any
	{
		// I1Dvaldclist(LCSRCsome1(srcgen2/DATS/go1emit_byref0.dats)@(4861(line=223,offs=3)--4913(line=223,offs=55)))
		goxtnm83 := xatsgo.Xats_a0ref_get
		goxtnm84 := goxtnm83(goxtnm60)
		goxtnm85 := goxtnm84
		_ = goxtnm85
		goxtnm86 := nient_memq_4413(goxtnm85, goxtnm81)
		var goxtnm92 any
		if goxtnm86 {
			goxtnm87 := struct{}{}
			goxtnm92 = goxtnm87
		} else {
			goxtnm88 := xatsgo.Xats_a0ref_set
			goxtnm89 := struct{F0 any; F1 any}{goxtnm81, goxtnm82}
			goxtnm90 := &xatsgo.XatsCon{Tag: 1, Args: []any{goxtnm89, goxtnm85}}
			goxtnm91 := goxtnm88(goxtnm60, goxtnm90)
			goxtnm92 = goxtnm91
		}
		goxtnm93 = goxtnm92
	}
	return goxtnm93
}

func nullary_inst_has_4525(goxtnm94 any) bool {
	goxtnm95 := xatsgo.Xats_a0ref_get
	goxtnm96 := goxtnm95(goxtnm60)
	goxtnm97 := nient_memq_4413(goxtnm96, goxtnm94)
	return goxtnm97
}

func nullary_inst_paramty_4851(goxtnm98 any) string {
	goxtnm99 := xatsgo.Xats_a0ref_get
	goxtnm100 := goxtnm99(goxtnm60)
	goxtnm101 := nient_find_4609(goxtnm100, goxtnm98)
	return goxtnm101
}

func inst_retty_add_6398(goxtnm106 any, goxtnm107 string) any {
	var goxtnm118 any
	{
		// I1Dvaldclist(LCSRCsome1(srcgen2/DATS/go1emit_byref0.dats)@(5543(line=252,offs=3)--5593(line=252,offs=53)))
		goxtnm108 := xatsgo.Xats_a0ref_get
		goxtnm109 := goxtnm108(goxtnm105)
		goxtnm110 := goxtnm109
		_ = goxtnm110
		goxtnm111 := nient_memq_4413(goxtnm110, goxtnm106)
		var goxtnm117 any
		if goxtnm111 {
			goxtnm112 := struct{}{}
			goxtnm117 = goxtnm112
		} else {
			goxtnm113 := xatsgo.Xats_a0ref_set
			goxtnm114 := struct{F0 any; F1 any}{goxtnm106, goxtnm107}
			goxtnm115 := &xatsgo.XatsCon{Tag: 1, Args: []any{goxtnm114, goxtnm110}}
			goxtnm116 := goxtnm113(goxtnm105, goxtnm115)
			goxtnm117 = goxtnm116
		}
		goxtnm118 = goxtnm117
	}
	return goxtnm118
}

func inst_retty_get_6613(goxtnm119 any) string {
	goxtnm120 := xatsgo.Xats_a0ref_get
	goxtnm121 := goxtnm120(goxtnm105)
	goxtnm122 := nient_find_4609(goxtnm121, goxtnm119)
	return goxtnm122
}

func goemit_ty_add_7670(goxtnm127 any, goxtnm128 string) any {
	var goxtnm139 any
	{
		// I1Dvaldclist(LCSRCsome1(srcgen2/DATS/go1emit_byref0.dats)@(6157(line=277,offs=3)--6206(line=277,offs=52)))
		goxtnm129 := xatsgo.Xats_a0ref_get
		goxtnm130 := goxtnm129(goxtnm126)
		goxtnm131 := goxtnm130
		_ = goxtnm131
		goxtnm132 := nient_memq_4413(goxtnm131, goxtnm127)
		var goxtnm138 any
		if goxtnm132 {
			goxtnm133 := struct{}{}
			goxtnm138 = goxtnm133
		} else {
			goxtnm134 := xatsgo.Xats_a0ref_set
			goxtnm135 := struct{F0 any; F1 any}{goxtnm127, goxtnm128}
			goxtnm136 := &xatsgo.XatsCon{Tag: 1, Args: []any{goxtnm135, goxtnm131}}
			goxtnm137 := goxtnm134(goxtnm126, goxtnm136)
			goxtnm138 = goxtnm137
		}
		goxtnm139 = goxtnm138
	}
	return goxtnm139
}

func goemit_ty_get_7717(goxtnm140 any) string {
	goxtnm141 := xatsgo.Xats_a0ref_get
	goxtnm142 := goxtnm141(goxtnm126)
	goxtnm143 := nient_find_4609(goxtnm142, goxtnm140)
	return goxtnm143
}

func dp2tr_ptr_add_5593(goxtnm148 any) any {
	var goxtnm158 any
	{
		// I1Dvaldclist(LCSRCsome1(srcgen2/DATS/go1emit_byref0.dats)@(6777(line=308,offs=3)--6826(line=308,offs=52)))
		goxtnm149 := xatsgo.Xats_a0ref_get
		goxtnm150 := goxtnm149(goxtnm147)
		goxtnm151 := goxtnm150
		_ = goxtnm151
		goxtnm152 := stmp_mem_1717(goxtnm151, goxtnm148)
		var goxtnm157 any
		if goxtnm152 {
			goxtnm153 := struct{}{}
			goxtnm157 = goxtnm153
		} else {
			goxtnm154 := xatsgo.Xats_a0ref_set
			goxtnm155 := &xatsgo.XatsCon{Tag: 1, Args: []any{goxtnm148, goxtnm151}}
			goxtnm156 := goxtnm154(goxtnm147, goxtnm155)
			goxtnm157 = goxtnm156
		}
		goxtnm158 = goxtnm157
	}
	return goxtnm158
}

func dp2tr_ptr_has_5630(goxtnm159 any) bool {
	goxtnm160 := xatsgo.Xats_a0ref_get
	goxtnm161 := goxtnm160(goxtnm147)
	goxtnm162 := stmp_mem_1717(goxtnm161, goxtnm159)
	return goxtnm162
}

var goxtnm16 any
func init() {
	goxtnm13 := xatsgo.Xats_a0ref_make_1val
	goxtnm14 := &xatsgo.XatsCon{Tag: 0, Args: []any{}}
	goxtnm15 := goxtnm13(goxtnm14)
	goxtnm16 = goxtnm15
}
var goxtnm44 any
func init() {
	goxtnm42 := xatsgo.Xats_a0ref_make_1val
	goxtnm43 := goxtnm42(false)
	goxtnm44 = goxtnm43
}
var goxtnm51 any
func init() {
	goxtnm49 := xatsgo.Xats_a0ref_make_1val
	goxtnm50 := goxtnm49(false)
	goxtnm51 = goxtnm50
}
var goxtnm60 any
func init() {
	goxtnm57 := xatsgo.Xats_a0ref_make_1val
	goxtnm58 := &xatsgo.XatsCon{Tag: 0, Args: []any{}}
	goxtnm59 := goxtnm57(goxtnm58)
	goxtnm60 = goxtnm59
}
var goxtnm105 any
func init() {
	goxtnm102 := xatsgo.Xats_a0ref_make_1val
	goxtnm103 := &xatsgo.XatsCon{Tag: 0, Args: []any{}}
	goxtnm104 := goxtnm102(goxtnm103)
	goxtnm105 = goxtnm104
}
var goxtnm126 any
func init() {
	goxtnm123 := xatsgo.Xats_a0ref_make_1val
	goxtnm124 := &xatsgo.XatsCon{Tag: 0, Args: []any{}}
	goxtnm125 := goxtnm123(goxtnm124)
	goxtnm126 = goxtnm125
}
var goxtnm147 any
func init() {
	goxtnm144 := xatsgo.Xats_a0ref_make_1val
	goxtnm145 := &xatsgo.XatsCon{Tag: 0, Args: []any{}}
	goxtnm146 := goxtnm144(goxtnm145)
	goxtnm147 = goxtnm146
}
func main() {
	xatsgo.XATS2GO_flush_pending()
}
