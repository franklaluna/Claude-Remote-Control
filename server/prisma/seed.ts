// 数据库种子 — 创建测试用户
import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  const email = 'admin@example.com';
  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) {
    console.log(`用户 ${email} 已存在，跳过`);
    return;
  }

  const hash = await bcrypt.hash('admin123', 10);
  await prisma.user.create({
    data: {
      email,
      password_hash: hash,
    },
  });
  console.log(`已创建测试用户: ${email} / admin123`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
