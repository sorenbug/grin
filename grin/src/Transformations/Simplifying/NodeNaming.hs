{-# LANGUAGE FlexibleContexts #-}

module Transformations.Simplifying.NodeNaming where

import Control.Monad
import Data.Functor.Foldable as Foldable

import Grin.Grin
import Transformations.Names

-- TODO: remove this
import Grin.Parse
import Grin.Pretty
import Transformations.BindNormalisation

newNodeName :: NameM Name
newNodeName = deriveNewName "node"

-- this transformation can invalidate the "no left bind" invariant
-- so we have to normalize these incorrect bindings
nameNodes :: Exp -> Exp
nameNodes e = evalNameM e . cata alg $ e where
  alg :: ExpF (NameM Exp) -> NameM Exp
  alg e = case e of
    SStoreF    x@VarTagNode{}   -> bindVal SStore x
    SStoreF    x@ConstTagNode{} -> bindVal SStore x
    SUpdateF p x@VarTagNode{}   -> bindVal (SUpdate p) x
    SUpdateF p x@ConstTagNode{} -> bindVal (SUpdate p) x
    SReturnF   x@VarTagNode{}   -> bindVal SReturn x
    SReturnF   x@ConstTagNode{} -> bindVal SReturn x
    expf -> fmap embed . sequence $ expf

  -- binds a Val (usually a node) to a name, then performs some action on it
  bindVal :: (Val -> Exp) -> Val -> NameM Exp
  bindVal context val = do
    nodeVar <- fmap Var newNodeName
    return $ SBlock $ EBind (SReturn val) nodeVar (context nodeVar)
