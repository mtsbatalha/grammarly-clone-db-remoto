import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Starting database seed...');

  // Create demo user
  const passwordHash = await bcrypt.hash('demo1234', 12);

  const demoUser = await prisma.user.upsert({
    where: { email: 'demo@grammarclone.com' },
    update: {},
    create: {
      email: 'demo@grammarclone.com',
      passwordHash,
      name: 'Usuário Demo',
      plan: 'PRO',
      preferredLanguage: 'PT_BR',
      dailyChecksLimit: 1000,
      settings: {
        create: {
          enableGrammar: true,
          enableSpelling: true,
          enablePunctuation: true,
          enableStyle: true,
          enableTone: true,
          enableClarity: true,
          preferredTone: 'NEUTRAL',
          showInlineCorrections: true,
          autoCorrect: false,
          darkMode: false,
        },
      },
    },
  });

  console.log(`✅ Created demo user: ${demoUser.email}`);

  // Create demo statistics
  await prisma.userStatistics.upsert({
    where: { userId: demoUser.id },
    update: {},
    create: {
      userId: demoUser.id,
      totalDocuments: 5,
      totalCorrections: 127,
      totalWordsChecked: 15420,
      grammarErrors: 45,
      spellingErrors: 32,
      punctuationErrors: 28,
      styleIssues: 15,
      toneAdjustments: 7,
      correctionsAccepted: 98,
      correctionsIgnored: 29,
      currentStreak: 5,
      longestStreak: 12,
      lastActiveDate: new Date(),
    },
  });

  console.log('✅ Created user statistics');

  // Create sample documents
  const documents = [
    {
      title: 'Carta de Apresentação',
      content: `<p>Prezados,</p>
<p>Venho por meio desta apresentar minha candidatura para a vaga de Desenvolvedor Full Stack. Com mais de 5 anos de experiência na área, acredito que posso contribuir significativamente para a equipe.</p>
<p>Minhas principais habilidades incluem:</p>
<ul>
<li>Desenvolvimento com React e Node.js</li>
<li>Experiência com bancos de dados SQL e NoSQL</li>
<li>Conhecimento em metodologias ágeis</li>
</ul>
<p>Agradeço a atenção e fico à disposição para uma entrevista.</p>
<p>Atenciosamente,<br>Usuário Demo</p>`,
      language: 'PT_BR',
      wordCount: 78,
      charCount: 523,
    },
    {
      title: 'Relatório Mensal',
      content: `<p>Este relatório apresenta os principais resultados do mês de janeiro.</p>
<p><strong>Métricas de Desempenho:</strong></p>
<ul>
<li>Usuários ativos: 1.250 (+15%)</li>
<li>Taxa de conversão: 3.2% (+0.5%)</li>
<li>Satisfação do cliente: 4.5/5</li>
</ul>
<p><strong>Próximos Passos:</strong></p>
<p>Focar na retenção de usuários e melhorar a experiência mobile.</p>`,
      language: 'PT_BR',
      wordCount: 52,
      charCount: 412,
    },
    {
      title: 'Meeting Notes - Q1 Planning',
      content: `<p>Date: January 15, 2024</p>
<p>Attendees: Team Leads, Product Manager</p>
<p><strong>Key Decisions:</strong></p>
<ul>
<li>Launch new feature by end of Q1</li>
<li>Increase marketing budget by 20%</li>
<li>Hire 2 new developers</li>
</ul>
<p><strong>Action Items:</strong></p>
<ol>
<li>Draft technical spec (Due: Jan 20)</li>
<li>Create hiring plan (Due: Jan 22)</li>
<li>Review marketing strategy (Due: Jan 25)</li>
</ol>`,
      language: 'EN_US',
      wordCount: 65,
      charCount: 438,
    },
  ];

  for (const doc of documents) {
    await prisma.document.create({
      data: {
        ...doc,
        userId: demoUser.id,
      },
    });
  }

  console.log(`✅ Created ${documents.length} sample documents`);

  console.log('');
  console.log('🎉 Seed completed successfully!');
  console.log('');
  console.log('📧 Demo credentials:');
  console.log('   Email: demo@grammarclone.com');
  console.log('   Password: demo1234');
  console.log('');
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
