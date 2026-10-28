local LazyTree = require(script.Parent._LazyTree)

return LazyTree("Assets", "Asset", function(child) return child end)
