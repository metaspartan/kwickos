package main

var essentialRecommends = map[string]bool{
	"ca-certificates": true,
	"netbase":         true,
}

func essentialRecommend(g []Dep) bool {
	for _, d := range g {
		if essentialRecommends[d.Name] {
			return true
		}
	}
	return false
}
