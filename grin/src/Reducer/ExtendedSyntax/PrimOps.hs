{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
module Reducer.ExtendedSyntax.PrimOps (evalPrimOp) where

import           Foreign.C.Types
import qualified Language.C.Inline as C
import qualified Language.C.Inline.Unsafe as CU
import Foreign.Marshal.Alloc
import Foreign.C.String


import Data.Bits (shift)
import Data.Char (chr, ord)
import Data.Map.Strict as Map
import Data.String (fromString)
import Data.Functor.Infix ((<$$>))
import Data.Text as Text
import Control.Monad.IO.Class

import Control.Concurrent (threadDelay)
import Data.Bits
import System.IO (hIsEOF, stdin)
import System.IO.Unsafe

import Grin.ExtendedSyntax.Grin
import Reducer.ExtendedSyntax.Base

C.include "<math.h>"
C.include "<stdio.h>"

-- primitive functions
primLiteralPrint _ _ [RT_Lit (LInt64 a)] = liftIO (print a) >> pure RT_Unit
primLiteralPrint _ _ [RT_Lit (LString a)] = liftIO (putStr (Text.unpack a)) >> pure RT_Unit
primLiteralPrint ctx ps x = error $ Prelude.unwords ["primLiteralPrint", ctx, "- invalid arguments:", show ps, " - ", show x]


evalPrimOp :: MonadIO m => Name -> [Name] -> [RTVal] -> m RTVal
evalPrimOp name params args = case name of
  "_prim_int_print"    -> primLiteralPrint "int"    params args
  "_prim_string_print" -> primLiteralPrint "string" params args
  "_prim_read_string"  -> primReadString
  "_prim_usleep"       -> primUSleep
  "_prim_error"        -> primError
  -- Conversion
  "_prim_int_str"      -> int_str
  "_prim_str_int"      -> str_int
  "_prim_int_float"    -> int_float
  "_prim_float_string" -> float_str
  "_prim_char_int"     -> char_int
  -- String
  "_prim_string_reverse" -> string_un_op string Text.reverse
  "_prim_string_head"    -> string_un_op int (fromIntegral . ord . Text.head)
  "_prim_string_tail"    -> string_un_op string Text.tail
  "_prim_string_len"     -> string_un_op int (fromIntegral . Text.length)
  "_prim_string_concat"  -> string_bin_op string (\t1 t2 -> Text.concat [t1, t2])
  "_prim_string_lt"      -> string_bin_op int (boolean 0 1 <$$> (<))
  "_prim_string_eq"      -> string_bin_op int (boolean 0 1 <$$> (==))
  "_prim_string_cons"    -> string_cons

  -- Int
  "_prim_int_shr"   -> int_un_op int (`shiftR` 1)
  "_prim_int_add"   -> int_bin_op int (+)
  "_prim_int_sub"   -> int_bin_op int (-)
  "_prim_int_mul"   -> int_bin_op int (*)
  "_prim_int_div"   -> int_bin_op int div
  "_prim_int_ashr"  -> int_bin_op int (\v h -> shift v ((-1) * fromIntegral h))
  "_prim_int_eq"    -> int_bin_op bool (==)
  "_prim_int_ne"    -> int_bin_op bool (/=)
  "_prim_int_gt"    -> int_bin_op bool (>)
  "_prim_int_ge"    -> int_bin_op bool (>=)
  "_prim_int_lt"    -> int_bin_op bool (<)
  "_prim_int_le"    -> int_bin_op bool (<=)
  -- Word
  "_prim_word_add"  -> word_bin_op word (+)
  "_prim_word_sub"  -> word_bin_op word (-)
  "_prim_word_mul"  -> word_bin_op word (*)
  "_prim_word_div"  -> word_bin_op word div
  "_prim_word_eq"   -> word_bin_op bool (==)
  "_prim_word_ne"   -> word_bin_op bool (/=)
  "_prim_word_gt"   -> word_bin_op bool (>)
  "_prim_word_ge"   -> word_bin_op bool (>=)
  "_prim_word_lt"   -> word_bin_op bool (<)
  "_prim_word_le"   -> word_bin_op bool (<=)
  -- Float
  "_prim_float_add" -> float_bin_op float (+)
  "_prim_float_sub" -> float_bin_op float (-)
  "_prim_float_mul" -> float_bin_op float (*)
  "_prim_float_div" -> float_bin_op float (/)
  "_prim_float_eq"  -> float_bin_op bool (==)
  "_prim_float_ne"  -> float_bin_op bool (/=)
  "_prim_float_gt"  -> float_bin_op bool (>)
  "_prim_float_ge"  -> float_bin_op bool (>=)
  "_prim_float_lt"  -> float_bin_op bool (<)
  "_prim_float_le"  -> float_bin_op bool (<=)
  -- Bool
  "_prim_bool_eq"   -> bool_bin_op bool (==)
  "_prim_bool_ne"   -> bool_bin_op bool (/=)
    -- FFI - TODO: Handle FFI appropiatey
  "_prim_ffi_file_eof" -> file_eof

  _ -> error $ "unknown primitive operation: " ++ unpackName name
 where
  int   x = pure . RT_Lit . LInt64 $ x
  word  x = pure . RT_Lit . LWord64 $ x
  float x = pure . RT_Lit . LFloat $ x
  bool  x = pure . RT_Lit . LBool $ x
  string x = pure . RT_Lit . LString $ x
--  char x = pure . RT_Lit . LChar $ x

  int_un_op retTy fn = case args of
    [RT_Lit (LInt64 a)] -> retTy $ fn a
    _ -> error $ "invalid arguments: " ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  int_bin_op retTy fn = case args of
    [RT_Lit (LInt64 a), RT_Lit (LInt64 b)] -> retTy $ fn a b
    _ -> error $ "invalid arguments: " ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  word_bin_op retTy fn = case args of
    [RT_Lit (LWord64 a), RT_Lit (LWord64 b)] -> retTy $ fn a b
    _ -> error $ "invalid arguments: " ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  float_bin_op retTy fn = case args of
    [RT_Lit (LFloat a), RT_Lit (LFloat b)] -> retTy $ fn a b
    _ -> error $ "invalid arguments: " ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  bool_bin_op retTy fn = case args of
    [RT_Lit (LBool a), RT_Lit (LBool b)] -> retTy $ fn a b
    _ -> error $ "invalid arguments: " ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  string_bin_op retTy fn = case args of
    [RT_Lit (LString a), RT_Lit (LString b)] -> retTy $ fn a b
    _ -> error $ "invalid arguments: " ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  string_un_op retTy fn = case args of
    [RT_Lit (LString a)] -> retTy $ fn a
    _ -> error $ "invalid arguments:" ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  string_cons = case args of
    [RT_Lit (LInt64 a), RT_Lit (LString b)] -> string $ Text.cons (chr (fromIntegral a)) b
    _ -> error $ "invalid arguments: " ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  int_str = case args of
    [RT_Lit (LInt64 a)] -> string $ fromString $ show a
    _ -> error $ "invalid arguments:" ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  str_int = case args of
    [RT_Lit (LString a)] -> int $ read $ Text.unpack a
    _ -> error $ "invalid arguments:" ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  int_float = case args of
    [RT_Lit (LInt64 a)] -> float $ fromIntegral a
    _ -> error $ "invalid arguments:" ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  char_int = case args of
    [RT_Lit (LChar a)] -> int . fromIntegral . ord $ a
    _ -> error $ "invalid arguments:" ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  float_str = case args of
    [RT_Lit (LFloat a)] -> liftIO $ allocaBytes 32 $ \buf -> do
        let cf = CFloat a
        [C.exp| void { snprintf($(char* buf), 32, "%.16g", $(float cf)) } |]
        string . fromString =<< peekCString buf

    _ -> error $ "invalid arguments:" ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  file_eof = case args of
    [RT_Lit (LInt64 0)] -> (fmap (\case { False -> 0; _ -> 1}) (liftIO (hIsEOF stdin))) >>= int
    _ -> error $ "invalid arguments:" ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  primReadString = case args of
    [] -> liftIO getLine >>= (string . fromString)
    _ -> error $ "invalid arguments:" ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  primUSleep = case args of
    [RT_Lit (LInt64 us)] -> liftIO $ threadDelay (fromIntegral us) >> pure RT_Unit
    _ -> error $ "invalid arguments:" ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  primError = case args of
    [RT_Lit (LString msg)] -> liftIO (ioError $ userError $ Text.unpack msg) >> pure RT_Unit
    _ -> error $ "invalid arguments:" ++ show params ++ " " ++ show args ++ " for " ++ unpackName name

  boolean f t x = if x then t else f