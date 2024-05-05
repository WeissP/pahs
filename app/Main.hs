import Data.Pass
import MyPrelude
import RIO.Process
import RIO.Text qualified as T
import UnliftIO.Environment (getArgs)

data AppEnv = AppEnv {_appPr :: PassRecord, _appPass :: PassEnv}
makeLenses ''AppEnv

instance HasPassRecord AppEnv where
  passRecord = appPr
instance HasProcessContext AppEnv where
  processContextL = appPass . processContextL
instance HasLogFunc AppEnv where
  logFuncL = appPass . logFuncL

main :: IO ()
main = do
  args <- getArgs
  let key = case args of
        (k : _) -> k
        _ -> error "the pass key need to be given"
  withEnv key $ disableFcitx >> autoType

withEnv :: String -> RIO AppEnv a -> IO a
withEnv key task = do
  logOptions <- logOptionsHandle stderr False
  ctx <- mkDefaultProcessContext
  withLogFunc logOptions $ \lf -> do
    let pEnv = PassEnv lf ctx
    pr <- runRIO pEnv (getPassRecord key)
    let aEnv = AppEnv pr pEnv
    runRIO aEnv task

data AutoType = TypePassTag PassTag | TypeTab | TypePassword

parseAutoType :: Text -> AutoType
parseAutoType "pass" = TypePassword
parseAutoType t = case T.stripPrefix ":" t of
  Just "tab" -> TypeTab
  Just unknown -> error $ "unknown key: " <> show unknown
  Nothing -> TypePassTag t

getAutoTypeCmds :: RIO AppEnv [AutoType]
getAutoTypeCmds = do
  a <- prProp_ "autotype"
  return $ parseAutoType <$> T.words a

xdotoolArgs :: AutoType -> RIO AppEnv [String]
xdotoolArgs (TypePassTag t) = do
  s <- prProp_ t
  return ["type", "--clearmodifiers", T.unpack s]
xdotoolArgs TypeTab = return ["key", "Tab"]
xdotoolArgs TypePassword = do
  pw <- view prPw
  return ["type", "--clearmodifiers", T.unpack pw]

runXdotool :: AutoType -> RIO AppEnv ()
runXdotool t = do
  args <- xdotoolArgs t
  proc "xdotool" args runProcess_

autoType :: RIO AppEnv ()
autoType = do
  cmds <- getAutoTypeCmds
  forM_ cmds runXdotool

disableFcitx :: RIO AppEnv ()
disableFcitx =
  handleAny
    logException
    (proc "fcitx5-remote" ["-s", "fcitx-keyboard-de-nodeadkeys"] runProcess_)
