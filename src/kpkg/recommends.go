package main

// Recommends are off by default (small installs), but a few recommended
// packages are what make the result usable at all - e.g. curl, wget, git and
// python3-requests without CA certificates cannot talk HTTPS. Those are
// always honoured.
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
