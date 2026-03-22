{ pkgs, pkgs-unstable, ... }:
let
  unstable = pkgs-unstable;
in
{
  programs.jujutsu = {
    enable = true;
    package = unstable.jujutsu;
    settings = {
      user = {
        name = "aidan";
        email = "aidanaden@hotmail.com";
      };

      aliases = {
        tug = [
          "bookmark"
          "move"
          "--from"
          "heads(::@- & bookmarks())"
          "--to"
          "@"
        ];

        "tug-" = [
          "bookmark"
          "move"
          "--from"
          "heads(::@- & bookmarks())"
          "--to"
          "@-"
        ];

        "rebase-all" = [
          "rebase"
          "-s"
          "roots(trunk()..mutable())"
          "-d"
          "trunk()"
        ];

        # Fetch, rebase, and clean up merged/stale bookmarks.
        sync = [
          "util"
          "exec"
          "--"
          "bash"
          "-c"
          ''
            set -e
            jj git fetch
            jj rebase-all

            # Delete local bookmarks that became empty after rebase (squash-merged into trunk)
            merged=$(jj log --no-graph \
              -r '(bookmarks() ~ main) & empty()' \
              -T 'local_bookmarks.map(|b| b.name()).join("\n") ++ "\n"' \
              2>/dev/null | sort -u | grep -v '^$' || true)
            if [ -n "$merged" ]; then
              echo 'Deleting merged bookmarks:'
              echo "$merged" | while read -r bm; do
                echo "  $bm"
                jj bookmark forget --include-remotes "$bm"
              done
            fi

            # Forget untracked remote bookmarks (stale refs from merged PRs)
            stale=$(jj log --no-graph \
              -r 'remote_bookmarks() ~ tracked_remote_bookmarks()' \
              -T 'remote_bookmarks.map(|b| b.name()).join("\n") ++ "\n"' \
              2>/dev/null | sort -u | grep -v '^$' || true)
            if [ -n "$stale" ]; then
              echo 'Forgetting stale remote bookmarks:'
              echo "$stale" | while read -r bm; do
                echo "  $bm"
                jj bookmark forget --include-remotes "$bm"
              done
            fi

            echo ""
            jj log -r 'trunk().. | trunk()'
          ''
        ];

        # Take content from any change, and move it into @.
        # - jj consume xyz path/to/file`
        consume = [
          "squash"
          "--into"
          "@"
          "--from"
        ];

        # Eject content from @ into any other change.
        # - jj eject xyz --interactive
        eject = [
          "squash"
          "--from"
          "@"
          "--into"
        ];
      };

      revsets = {
        # By default, show the current stack of work.
        # log = "stack(@)";
      };

      revset-aliases = {
        # trunk() by default resolves to the latest 'main'/'master' remote bookmark. May
        # require customization for repos like nixpkgs.
        "trunk()" = "latest((present(main@origin) | present(master@origin)) & remote_bookmarks())";

        # stack(x, n) is the set of mutable commits reachable from 'x', with 'n'
        # parents. 'n' is often useful to customize the display and return set for
        # certain operations. 'x' can be used to target the set of 'roots' to traverse,
        # e.g. @ is the current stack.
        "stack()" = "ancestors(reachable(@, mutable()), 2)";
        "stack(x)" = "ancestors(reachable(x, mutable()), 2)";
        "stack(x, n)" = "ancestors(reachable(x, mutable()), n)";
      };

      snapshot = {
        "auto-update-stale" = true;
      };

      git = {
        colocate = true;
      };

      ui = {
        "default-command" = "log";
        "diff-formatter" = [
          "difft"
          "--color=always"
          "$left"
          "$right"
        ];
      };

      merge-tools = {
        beads-merge = {
          program = "bd";
          merge-args = [ "merge" "$output" "$base" "$left" "$right" ];
          merge-conflict-exit-codes = [ 1 ];
        };
      };
    };
  };
}
