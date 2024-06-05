local MODREV, SPECREV = "scm", "-1"
rockspec_format = "3.0"
package = "neorg-conceal-wrap"
version = MODREV .. SPECREV

description = {
	summary = "Neorg module to hard wrap text based on it's concealed width",
	labels = { "neovim" },
	homepage = "https://github.com/benluas/neorg-conceal-wrap",
	license = "MIT",
}

source = {
	url = "http://github.com/benlubas/neorg-conceal-wrap/archive/v" .. MODREV .. ".zip",
}

if MODREV == "scm" then
	source = {
		url = "git://github.com/benlubas/neorg-conceal-wrap",
	}
end

dependencies = {
	"neorg ~> 8",
}
