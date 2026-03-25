import { defineConfig } from 'vitepress'

export default defineConfig({
  title: "Darian Hickman Manifesto",
  description: "Future Proofing Government",
  themeConfig: {
    nav: [
      { text: 'Home', link: '/' }
    ],
    sidebar: [
      {
        text: 'The Manifesto',
        items: [
          { text: 'Combined Manifesto', link: '/Combined_Manifesto' },
          { text: 'Numerica Core', link: '/Numerica' },
          { text: 'Problems Surfaced', link: '/Problems that Surface in Last 100 Years' },
          { text: 'Problems Solved', link: '/Problems that have Been Solved Already' },
          { text: 'Plan to Rebuild', link: '/PlanRebuildGovernment' }
        ]
      }
    ],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/darianmavgo/manifesto' }
    ]
  }
})
