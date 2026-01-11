//go:build tools
// +build tools

package tools

import (
	// 基础绑定包
	_ "golang.org/x/mobile/bind"
	// 【关键】iOS 必须显式引用这个，否则会被 go mod tidy 删掉
	_ "golang.org/x/mobile/bind/objc"
)
