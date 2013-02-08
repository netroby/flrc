(* IFLC/IHC *)
(* COPYRIGHT_NOTICE_1 *)

signature ANORM_STRICT_STATS =
sig
  datatype options = O of {id: string option}
  val layout : options -> ANormStrict.t * Config.t -> Layout.t
  (*
   * Due to typeManager requirement, it's difficult to implement the function below:
   * val module : Config.t * ANormStrict.tm * options * ANormStrict.module * Out.t -> unit 
   *)
  val program : Config.t * options * ANormStrict.t * Out.t -> unit
end;

structure ANormStrictStats :> ANORM_STRICT_STATS =
struct

  val passname = "ANormStrictStats"

  structure ANS = ANormStrict
  structure SS = StringSet
  structure I = Identifier
  structure L = Layout

  datatype options = O of {id: string option}

  datatype env = E of {config: Config.t, tm : ANS.typeManager, options: options}

  val envMk = fn (c, tm, opts) => E {config = c, tm = tm, options = opts}

  val getTM = fn (E { tm = tm, ... }) => tm

  datatype state = S of {
                   tySet    : SS.t ref,
                   expNodes : int ref,
                   tyNodes  : int ref,
                   varUses  : int ref,
                   vExps    : int ref,
                   vFuns    : int ref,
                   vThks    : int ref
                 }

  val stateMk =
   fn () => 
      S {tySet = ref SS.empty, expNodes = ref 0, tyNodes = ref 0, varUses = ref 0, vExps = ref 0, vFuns = ref 0, vThks = ref 0}

  val incr = fn r => r := (!r) + 1

  val incrF = fn sel => fn (S r) => incr (sel r)
  val incrExpNodes = incrF #expNodes
  val incrTyNodes = incrF #tyNodes
  val incrVarUses = incrF #varUses
  val incrVExps = incrF #vExps
  val incrVFuns = incrF #vFuns
  val incrVThks = incrF #vThks
  val insertTyNode = 
   fn (S { tySet = tySet, ... }, env, ty) => 
     tySet := SS.insert (!tySet, TypeRep.hashRep (getTM env, ty))

  val variableUse = fn (s, e, _) => incrVarUses s
  val analyzeExp = fn (s, e, _) => incrExpNodes s
  val analyzeTy = fn (s, e, t) => incrTyNodes s before insertTyNode (s, e, t)

  val analyzeVDefg = fn (s, e, vdg) => 
                        let
                          val () =
                              case vdg
                               of ANS.Vdef _ => incrVExps s
                                | _          => ()
                        in e
                        end
  val analyzeVDef = fn (s, e, vd) => 
                       (case vd
                         of ANS.Vfun _ => incrVFuns s
                          | ANS.Vthk _ => incrVThks s)

  structure A = ANormStrictAnalyzeF(type state = state
                                    type env = env
                                    val config = fn (E {config, ...}) => config
                                    val variableBind = NONE
                                    val variableUse = SOME variableUse
                                    val analyzeTy = SOME analyzeTy
                                    val analyzeExp = SOME analyzeExp
                                    val analyzeAlt = NONE
                                    val analyzeVDef = SOME analyzeVDef
                                    val analyzeVDefg = SOME analyzeVDefg)
  val layoutStats = 
   fn (s, e, O {id, ...}) =>
      let
        val S {tySet, expNodes, tyNodes, varUses, vExps, vFuns, vThks} = s
        val doOne = fn (s, r) => L.seq [L.str ("  Number of " ^ s), Int.layout r]
        val l = L.align [doOne ("exp nodes:          ", !expNodes),
                         doOne ("ty nodes:           ", !tyNodes),
                         doOne ("ty nodes (unique):  ", SS.size (!tySet)),
                         doOne ("ty nodes (managed): ", TypeRep.size (getTM e)),
                         doOne ("var uses:           ", !varUses),
                         doOne ("exp bindings:       ", !vExps),
                         doOne ("fun bindings:       ", !vFuns),
                         doOne ("thk bindings:       ", !vThks)]
        val l =
            case id
             of NONE => l
              | SOME id =>
                L.align [L.str ("---------- Stats for: " ^ id),
                         l,
                         L.str ("---------- End stats for: " ^ id ^ "\n")]
      in l
      end

  val layoutMk =
   fn doIt => 
      fn opts => fn (p as (_, _, tm), config) =>
         let
           val s = stateMk ()
           val e = envMk (config, tm, opts)
           val () = doIt (s, e, p)
           val l = layoutStats (s, e, opts)
         in l
         end

  (*
  val module =
   fn (config, opts, m, out) =>
      Layout.outputWidth (layoutMk A.module opts (m, config), 78, out)
  *)
        
  val layout = layoutMk A.program

  val program =
   fn (config, opts, p, out) =>
      Layout.outputWidth (layout opts (p, config), 78, out)

end;