package docker

import rego.v1

approved_base_prefixes := {
	"pytorch/", 
	"python:", 
	"python@",
	"seldonio/", 
	"amazon/",
	"public.ecr.aws/",
}

from_images contains img if {
	instr := input[_]
	instr.Cmd == "from"
	img := instr.Value[0]
}

stage_aliases contains lower(alias) if {
	instr := input[_]
	instr.Cmd == "from"
	count(instr.Value) >= 3
	upper(instr.Value[1]) == "AS"
	alias := instr.Value[2]
}

is_ecr(img) if regex.match(`^[0-9]+\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/`, img)

is_approved(img) if {
	some prefix in approved_base_prefixes
	startswith(img, prefix)
}

is_approved(img) if is_ecr(img)

is_stage_ref(img) if stage_aliases[lower(img)]

deny contains msg if {
	some img in from_images
	not is_stage_ref(img)
	not is_approved(img)
	msg := sprintf("base image %q is not from an approved registry (allowed: %v or the org ECR)", [img, approved_base_prefixes])
}

deny contains msg if {
	instr := input[_]
	instr.Cmd == "run"
	cmd := concat(" ", instr.Value)
	regex.match(`(?i)(curl|wget)[^|]*\|\s*(sudo\s+)?(ba)?sh`, cmd)
	msg := sprintf("RUN pipes a remote script into a shell (%q) — download, verify, then execute", [cmd])
}

warn contains msg if {
	some img in from_images
	not is_stage_ref(img)
	endswith(img, ":latest")
	msg := sprintf("base image %q uses the mutable :latest tag — pin a version", [img])
}
