/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements. See the NOTICE file distributed with this
 * work for additional information regarding copyright ownership. The ASF
 * licenses this file to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations
 * under the License.
 */
package org.apache.hadoop.hbase.procedure;

import static org.junit.Assert.fail;

import java.io.IOException;
import java.util.List;
import java.util.Optional;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.hbase.HBaseTestingUtility;
import org.apache.hadoop.hbase.TableName;
import org.apache.hadoop.hbase.client.RegionInfo;
import org.apache.hadoop.hbase.client.TableDescriptor;
import org.apache.hadoop.hbase.coprocessor.CoprocessorHost;
import org.apache.hadoop.hbase.coprocessor.MasterCoprocessor;
import org.apache.hadoop.hbase.coprocessor.MasterCoprocessorEnvironment;
import org.apache.hadoop.hbase.coprocessor.MasterObserver;
import org.apache.hadoop.hbase.coprocessor.ObserverContext;
import org.apache.hadoop.hbase.procedure2.Procedure;
import org.apache.hadoop.hbase.security.AccessDeniedException;
import org.apache.hadoop.hbase.shaded.protobuf.generated.ProcedureProtos;
import org.apache.hadoop.hbase.testclassification.MediumTests;
import org.apache.hadoop.hbase.util.Bytes;
import org.junit.AfterClass;
import org.junit.BeforeClass;
import org.junit.Test;
import org.junit.experimental.categories.Category;

/**
 * Check if CompletedProcedureCleaner cleans up failed nonce procedures.
 */
@Category(MediumTests.class)
public class TestFailedProcCleanup {
  private static final Log LOG = LogFactory.getLog(TestFailedProcCleanup.class);

  protected static HBaseTestingUtility TEST_UTIL = new HBaseTestingUtility();
  private static final TableName TABLE = TableName.valueOf("test");
  private static final byte[] FAMILY = Bytes.toBytesBinary("f");
  private static final int evictionDelay = 10 * 1000;

  @BeforeClass
  public static void setUpBeforeClass() throws Exception {
    Configuration conf = TEST_UTIL.getConfiguration();
    conf.setInt("hbase.procedure.cleaner.evict.ttl", evictionDelay);
    conf.setInt("hbase.procedure.cleaner.evict.batch.size", 1);
    conf.set(CoprocessorHost.MASTER_COPROCESSOR_CONF_KEY, CreateFailObserver.class.getName());
    TEST_UTIL.startMiniCluster(3);
  }

  @AfterClass
  public static void tearDownAfterClass() throws Exception {
    TEST_UTIL.cleanupTestDir();
    TEST_UTIL.cleanupDataTestDirOnTestFS();
    TEST_UTIL.shutdownMiniCluster();
  }

  @Test
  public void testFailCreateTable() throws Exception {
    try {
      TEST_UTIL.createTable(TABLE, FAMILY);
      fail("Table shouldn't be created");
    } catch (AccessDeniedException e) {
      LOG.debug("Ignoring exception: ", e);
      Thread.sleep(evictionDelay * 3);
    }
    List<Procedure<?>> procedureInfos =
        TEST_UTIL.getMiniHBaseCluster().getMaster().getMasterProcedureExecutor().getProcedures();
    for (Procedure procedureInfo : procedureInfos) {
      if (procedureInfo.getProcName().equals("CreateTableProcedure")
          && procedureInfo.getState() == ProcedureProtos.ProcedureState.ROLLEDBACK) {
        fail("Found procedure " + procedureInfo + " that hasn't been cleaned up");
      }
    }
  }

  public static class CreateFailObserver implements MasterCoprocessor, MasterObserver {

    @Override
    public void preCreateTable(ObserverContext<MasterCoprocessorEnvironment> env,
        TableDescriptor desc, RegionInfo[] regions) throws IOException {

      if (desc.getTableName().equals(TABLE)) {
        throw new AccessDeniedException("Don't allow creation of table");
      }
    }

    @Override
    public Optional<MasterObserver> getMasterObserver() {
      return Optional.of(this);
    }
  }
}
